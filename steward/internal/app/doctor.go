package app

// `doctor` (observe): check what the box needs and surface what's missing. Handy in
// development and before a deploy. Pure-ish: the checks take an injected path lookup
// so the logic is testable without the real tools installed.

import (
	"steward/internal/core"

	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
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
	// Disk, said in a way that can be acted on. "82% full" is a fact; "3 unreferenced
	// images" is a next step. doctor prescribes and never performs — it runs
	// unprivileged, it is an observe verb, and a read that quietly changed the box
	// would be the one thing this design refuses.
	unref, totalImages := unreferencedImageCount()
	checks = append(checks, diskCheck(diskUsedPercent(), unref, totalImages))
	if _, err := exec.LookPath("caddy"); err == nil {
		checks = append(checks, caddyAdminCheck(dialCaddyAdmin()))
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

// Disk thresholds. `warn` is where an operator should act before it is urgent; the
// console uses the same numbers for its pressure badges, so the box and the lens agree
// about what "running low" means.
const (
	diskWarnPercent = 75
	diskCritPercent = 90
)

// diskCheck turns a percentage into an instruction. Ordered by what the operator should
// do first: unreferenced images are the cheapest space on the box and the most common
// cause, so they lead when there are any.
//
// It fails the check only on real pressure — holding a few spare images is not a fault,
// and a doctor that cries about a healthy box teaches people to ignore it.
func diskCheck(usedPct, unreferenced, totalImages int) check {
	c := check{Name: "disk", OK: usedPct < diskCritPercent}

	var parts []string
	if usedPct > 0 {
		parts = append(parts, fmt.Sprintf("%d%% used", usedPct))
	}
	if totalImages > 0 {
		parts = append(parts, fmt.Sprintf("%d image%s, %d unreferenced", totalImages, plural(totalImages), unreferenced))
	}

	// The prescription, most actionable first.
	switch {
	case unreferenced > 0 && usedPct >= diskWarnPercent:
		parts = append(parts, fmt.Sprintf("free space now: `podman rmi $(podman images -q)` drops the %d unreferenced, or the next deploy prunes them", unreferenced))
	case unreferenced > 0:
		parts = append(parts, "the next deploy prunes them; nothing to do")
	case usedPct >= diskCritPercent:
		parts = append(parts, "no images to reclaim — check app volumes and `journalctl --disk-usage`")
	case usedPct >= diskWarnPercent:
		parts = append(parts, "no images to reclaim — worth watching")
	}
	c.Note = strings.Join(parts, "; ")
	return c
}

// diskUsedPercent is the root filesystem, rounded. 0 when it cannot be read, which makes
// the check say nothing rather than assert something false.
func diskUsedPercent() int {
	var st syscall.Statfs_t
	if err := syscall.Statfs("/", &st); err != nil || st.Blocks == 0 {
		return 0
	}
	total := st.Blocks * uint64(st.Bsize) // #nosec G115 -- statfs block size is small and positive
	free := st.Bavail * uint64(st.Bsize)  // #nosec G115 -- same
	if total == 0 {
		return 0
	}
	return int(100 * (total - free) / total) // #nosec G115 -- a percentage, bounded 0..100
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

// caddyAdminCheck says whether Caddy's admin API is where prepare put it: on the socket,
// which only the caddy user and the steward group may open, and not on localhost:2019,
// where anyone on the box may replace the config. sockErr is this user's attempt to
// connect to the socket; tcpOpen is whether anything answers on the old port.
func caddyAdminCheck(sockErr error, tcpOpen bool) check {
	const name = "caddy admin on its socket only"
	switch {
	case tcpOpen:
		return check{Name: name, OK: false,
			Note: "something answers on localhost:2019, where any local user can rewrite Caddy's config — re-run 'sudo steward prepare'"}
	case sockErr != nil:
		return check{Name: name, OK: false,
			Note: "cannot open " + caddyAdminSocket + " (" + sockErr.Error() + ") — is Caddy running? re-run 'sudo steward prepare' if it is"}
	}
	return check{Name: name, OK: true, Note: caddyAdminSocket}
}

// dialCaddyAdmin connects to both admin addresses and hangs up without sending anything:
// the question is only who could talk to Caddy, so no request is ever made.
func dialCaddyAdmin() (sockErr error, tcpOpen bool) {
	if c, err := net.DialTimeout("unix", caddyAdminSocket, time.Second); err == nil {
		_ = c.Close()
	} else {
		sockErr = err
	}
	if c, err := net.DialTimeout("tcp", "127.0.0.1:2019", time.Second); err == nil {
		_ = c.Close()
		tcpOpen = true
	}
	return sockErr, tcpOpen
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
