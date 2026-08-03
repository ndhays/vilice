package app

// `doctor` (observe): check what the box needs and surface what's missing. Handy in
// development and before a deploy. Pure-ish: the checks take an injected path lookup
// so the logic is testable without the real tools installed.

import (
	"steward/internal/core"

	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// quadletMin is the lowest Podman that ships Quadlet (the .container generator), which
// the deploy path now relies on. See decisions/open/quadlet-units.md.
const quadletMinMajor, quadletMinMinor = 4, 4

type check struct {
	Name string `json:"name"`
	OK   bool   `json:"ok"`
	Note string `json:"note,omitempty"`
}

func doctorCmd(args []string) core.Result {
	checks := runChecks(exec.LookPath, func() (string, error) { return podmanOutput("--version") })
	// Registry coverage: which registries the deployed apps reference, and which the box
	// has a login for. Informational (a missing login may just be a public registry).
	apps, _ := listApps()
	checks = append(checks, registryCoverageCheck(apps, loggedInRegistries()))
	// Ghost containers: steward run as the wrong user deploys into *that* user's
	// rootless-podman world — invisible to this one. Detect the residue by the
	// per-container conmon processes any podman leaves running.
	if out, err := exec.Command("ps", "-eo", "uid=,comm=").Output(); err == nil {
		checks = append(checks, ghostContainerCheck(string(out), os.Geteuid()))
	}
	// Did an upgrade land the binary somewhere new? Both reads are best-effort: on a box
	// with neither the unit nor a ledger there is nothing to compare, so nothing is said.
	if self, err := os.Executable(); err == nil {
		unit, _ := os.ReadFile(core.SnapshotServicePath)
		var keys []byte
		if kp, kerr := core.AuthorizedKeysPath(); kerr == nil {
			keys, _ = os.ReadFile(kp) // #nosec G304 -- steward's own ledger path
		}
		if len(unit) > 0 || len(keys) > 0 {
			checks = append(checks, binaryPathCheck(self, string(unit), string(keys)))
		}
	}
	failed := 0
	for _, c := range checks {
		if !c.OK {
			failed++
		}
	}
	code := "ok"
	if failed > 0 {
		code = "problems_found"
	}
	// A pointer, not a check: hardening is optional and needs root, so doctor (which
	// runs unprivileged) doesn't run it — it just points the way. See harden --check.
	msg := renderChecks(checks) + "\n\nhardening  run 'sudo steward harden --check' to verify (optional, separate)"
	return core.Result{Code: code, Message: msg, Data: checks}
}

// runChecks reports on the tools Steward drives and the record floor. look and
// podmanVer let a test stand in for exec.LookPath and `podman --version`.
func runChecks(look func(string) (string, error), podmanVer func() (string, error)) []check {
	var cs []check
	for _, tool := range []string{"podman", "caddy", "restic", "systemctl"} {
		_, err := look(tool)
		c := check{Name: tool, OK: err == nil}
		if err != nil {
			c.Note = "not found in PATH"
		}
		cs = append(cs, c)
	}
	cs = append(cs, podmanQuadletCheck(podmanVer))
	cs = append(cs, dirCheck("record dir", filepath.Dir(core.RecordPath())))
	if kp, err := core.AuthorizedKeysPath(); err == nil {
		cs = append(cs, dirCheck("authorized_keys dir", filepath.Dir(kp)))
	}
	return cs
}

// podmanQuadletCheck verifies Podman is new enough for Quadlet (>= 4.4). The version
// read is injected; the parsing is pure (parsePodmanVersion).
func podmanQuadletCheck(podmanVer func() (string, error)) check {
	const name = "podman >= 4.4 (quadlet)"
	out, err := podmanVer()
	if err != nil {
		return check{Name: name, OK: false, Note: "could not read podman version"}
	}
	maj, min, ok := parsePodmanVersion(out)
	if !ok {
		return check{Name: name, OK: false, Note: "unrecognized version: " + strings.TrimSpace(out)}
	}
	if !quadletReady(maj, min) {
		return check{Name: name, OK: false, Note: fmt.Sprintf("found %d.%d — Quadlet needs >= 4.4", maj, min)}
	}
	return check{Name: name, OK: true, Note: fmt.Sprintf("%d.%d", maj, min)}
}

func quadletReady(maj, min int) bool {
	return maj > quadletMinMajor || (maj == quadletMinMajor && min >= quadletMinMinor)
}

// parsePodmanVersion reads the last whitespace-separated token of `podman --version`
// output ("podman version 5.7.0") as major.minor.
func parsePodmanVersion(out string) (int, int, bool) {
	fields := strings.Fields(strings.TrimSpace(out))
	if len(fields) == 0 {
		return 0, 0, false
	}
	parts := strings.SplitN(fields[len(fields)-1], ".", 3)
	if len(parts) < 2 {
		return 0, 0, false
	}
	maj, err1 := strconv.Atoi(parts[0])
	min, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil {
		return 0, 0, false
	}
	return maj, min, true
}

// ghostContainerCheck flags containers running under any uid but ours — the
// residue of steward run as the wrong user (see decisions/one-steward-per-box.md;
// the wrong_user gate refuses new ones, this surfaces ones already running).
// psOut is `ps -eo uid=,comm=`; conmon is podman's per-container monitor.
func ghostContainerCheck(psOut string, selfUID int) check {
	const name = "containers run as the steward user only"
	ghosts := map[int]int{} // uid → running containers
	for _, ln := range core.NonEmptyLines(psOut) {
		f := strings.Fields(ln)
		if len(f) < 2 || f[1] != "conmon" {
			continue
		}
		if uid, err := strconv.Atoi(f[0]); err == nil && uid != selfUID {
			ghosts[uid]++
		}
	}
	if len(ghosts) == 0 {
		return check{Name: name, OK: true}
	}
	var parts []string
	for uid, n := range ghosts {
		parts = append(parts, fmt.Sprintf("%d under uid %d", n, uid))
	}
	sort.Strings(parts)
	return check{Name: name, OK: false,
		Note: "ghost containers (" + strings.Join(parts, ", ") + ") — was steward run as the wrong user?"}
}

// binaryPathCheck reports whether the paths baked into the box still point at this
// binary.
//
// The absolute path lands in two places at install time: the snapshot unit's ExecStart,
// and the forced command of *every* scoped key. Re-running `prepare` rewrites the unit,
// but nothing rewrites a key's line except `authorize` — so installing to a new path
// leaves every scoped key aimed at a binary that isn't there, and the repair is
// re-authorizing every client. Quiet until Steward Console can't reach the box, which is why
// doctor says it out loud. Upgrade in place; see blueprint/steward/provision.md.
//
// Pure so the parsing is testable: unit is the .service text, authKeys the ledger.
func binaryPathCheck(self, unit, authKeys string) check {
	const name = "binary path matches the box"
	stale := map[string][]string{} // path -> where it is still referenced

	if p := execStartPath(unit); p != "" && p != self {
		stale[p] = append(stale[p], "the snapshot timer")
	}
	clients := 0
	for _, ln := range core.NonEmptyLines(authKeys) {
		p := forcedCommandPath(ln)
		if p != "" && p != self {
			clients++
		}
	}
	if clients > 0 {
		for _, ln := range core.NonEmptyLines(authKeys) {
			if p := forcedCommandPath(ln); p != "" && p != self {
				stale[p] = append(stale[p], fmt.Sprintf("%d scoped key(s)", clients))
				break
			}
		}
	}
	if len(stale) == 0 {
		return check{Name: name, OK: true, Note: self}
	}
	var parts []string
	for p, where := range stale {
		parts = append(parts, fmt.Sprintf("%s still points at %s", strings.Join(where, " and "), p))
	}
	sort.Strings(parts)
	return check{Name: name, OK: false, Note: fmt.Sprintf(
		"this binary is %s, but %s — re-run prepare, and re-authorize each client",
		self, strings.Join(parts, "; "))}
}

// execStartPath pulls the executable out of a unit's ExecStart= line ("" if absent).
func execStartPath(unit string) string {
	for _, ln := range core.NonEmptyLines(unit) {
		if rest, found := strings.CutPrefix(strings.TrimSpace(ln), "ExecStart="); found {
			return strings.TrimSpace(strings.Fields(rest)[0])
		}
	}
	return ""
}

// forcedCommandPath pulls the executable out of an authorized_keys command="…" option
// ("" if the line has none).
func forcedCommandPath(line string) string {
	rest, found := strings.CutPrefix(strings.TrimSpace(line), `command="`)
	if !found {
		return ""
	}
	cmd, _, found := strings.Cut(rest, `"`)
	if !found || strings.TrimSpace(cmd) == "" {
		return ""
	}
	return strings.Fields(cmd)[0]
}

func dirCheck(name, dir string) check {
	info, err := os.Stat(dir)
	switch {
	case err == nil && info.IsDir():
		return check{Name: name, OK: true, Note: dir}
	case err == nil:
		return check{Name: name, OK: false, Note: dir + " is not a directory"}
	default:
		return check{Name: name, OK: false, Note: dir + " missing (run prepare)"}
	}
}

func renderChecks(cs []check) string {
	var b strings.Builder
	for _, c := range cs {
		mark := "ok  "
		if !c.OK {
			mark = "FAIL"
		}
		line := fmt.Sprintf("[%s] %s", mark, c.Name)
		if c.Note != "" {
			line += "  — " + c.Note
		}
		b.WriteString(line + "\n")
	}
	return strings.TrimRight(b.String(), "\n")
}
