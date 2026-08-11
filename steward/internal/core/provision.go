package core

// `prepare` (root-only ceiling): the steward-specific setup — install the tools
// Steward drives and lay the accountability floor. The generic OS hardening lives
// separately in `harden` (harden.go + the embedded harden/ folder), which knows
// nothing about steward. See blueprint/steward/provision.md. prepare mutates the
// machine, so it runs as root on the box and is verified there, not unit-tested.
// Every step is idempotent: re-running converges.

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const StewardUser = "steward"

// The units `prepare` installs. Named once: `uninstall` removes them and `doctor` reads
// the service back to check the binary path baked into it.
const (
	SnapshotServicePath = "/etc/systemd/system/steward-snapshot.service"
	snapshotTimerPath   = "/etc/systemd/system/steward-snapshot.timer"
)

func prepareCmd(args []string) Result {
	if os.Geteuid() != 0 {
		return Result{Code: "not_root", Message: "prepare must run as root"}
	}
	yes := hasFlag(args, "-y", "--yes")

	role, err := roleFromArgs(args)
	if err != nil {
		return Result{Code: "bad_args", Message: err.Error()}
	}
	// Refuse a *change* of role before installing anything, so a mistyped conversion
	// costs nothing. Re-stating the same role is idempotent, like the rest of prepare.
	if err := SetRole(role); err != nil {
		return Result{Code: "bad_args", Message: err.Error()}
	}

	fmt.Println("\n=== apt update ===")
	if err := aptUpdate(); err != nil {
		return Result{Code: "prepare_failed", Retryable: true, Message: "apt update: " + err.Error()}
	}

	// apt-style courtesy: show what's coming and ask, unless --yes. What is coming
	// is whatever this role needs — the ceiling does not know or care what any of it
	// is for, only that the operator consents to it once, up front.
	if !confirmInstall(appSubstrate(role), yes) {
		return Result{Code: "aborted", Message: "prepare cancelled — nothing installed"}
	}

	// The floor first, then the substrate. The app layer's Prepare may rely on the
	// steward account and the record existing; nothing in the floor may rely on it.
	steps := []struct {
		name string
		fn   func() error
	}{
		{"create steward user", ensureStewardUser},
		{"grant OS-update privilege", ensureUpdatePrivilege},
		{"lay accountability floor", ensureFloor},
		{"record the role", func() error { return recordRole(role) }},
		{"record this binary's digest", recordBinaryDigest},
		{"install what the role needs", func() error { return prepareApps(role) }},
		{"open the role's ports", func() error { return openRolePorts(role) }},
		{"install snapshot timer", ensureSnapshotTimer},
	}
	for _, s := range steps {
		fmt.Printf("\n=== %s ===\n", s.name)
		if err := s.fn(); err != nil {
			return Result{Code: "prepare_failed", Retryable: true, Message: fmt.Sprintf("%s: %v", s.name, err)}
		}
	}
	printPrepareSummary()
	return OK("box prepared")
}

// appSubstrate is what this role needs installed, asked of the app layer so the
// ceiling can show the operator one list before anything is installed.
func appSubstrate(role string) Substrate {
	if apps == nil {
		return Substrate{}
	}
	return apps.Substrate(role)
}

// prepareApps lets the app layer install and configure its own substrate. The
// ceiling runs it and reports failure; it never learns what was installed. If this
// function ever needs to know, the line has moved.
func prepareApps(role string) error {
	if apps == nil {
		return nil
	}
	return apps.Prepare(role)
}

// recordBinaryDigest writes down which binary this box authorizes: the one running
// prepare. Until it exists, no verb that acts runs — a box that has not said which
// binary may run says no.
//
// The file is root-owned under /etc, which is the enforcement: the steward user can
// read it and cannot write it, so no scoped key can authorize a different binary.
// Doing so is a root act at the ceiling, exactly like the rest of prepare.
//
// It is also an entry in the chain, so "which binary was ever allowed to run on this
// box, and when" is answerable from the record alone.
func recordBinaryDigest() error {
	digest, err := writeBinaryDigest()
	if err != nil {
		return fmt.Errorf("writing %s: %w", BinaryDigestPath(), err)
	}
	fmt.Printf("  this box authorizes %s\n", digest)
	return RecordAct(ActorName(), string(ScopeRoot), "authorize-binary", []string{digest}, digest)
}

// sudoersForUpdates is the steward user's one narrow root escalation: applying OS
// updates (apply-updates is operate-scoped, so it runs as the unprivileged steward
// user, but apt needs root). Exactly the two apt commands aptUpdateCommands() runs,
// with fixed args — so a key-holder who can issue apply-updates can run *those two
// things as root and nothing else*. The ceiling stays small and legible.
func sudoersForUpdates() string {
	return fmt.Sprintf(`# Managed by `+"`steward prepare`"+`. The steward user runs unprivileged; this is its
# one narrow root escalation — apply OS updates (the apply-updates command).
%s ALL=(root) NOPASSWD: /usr/bin/apt-get update -y, /usr/bin/apt-get upgrade -y
`, StewardUser)
}

// ensureUpdatePrivilege installs that grant at /etc/sudoers.d/steward, validated by
// visudo before it goes live (a malformed sudoers file is dangerous), mode 0440.
func ensureUpdatePrivilege() error {
	const path = "/etc/sudoers.d/steward"
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(sudoersForUpdates()), 0o440); err != nil {
		return err
	}
	if err := exec.Command("visudo", "-cf", tmp).Run(); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("refusing to install an invalid sudoers grant: %w", err)
	}
	fmt.Println("steward may apply OS updates via a narrow sudoers grant")
	return os.Rename(tmp, path)
}

// harden lives in harden.go (an embedded, steward-agnostic bash unit).

// --- steps ---

func aptUpdate() error { return Sh("apt-get update -y") }

func ensureStewardUser() error {
	if exec.Command("id", StewardUser).Run() == nil {
		fmt.Println("steward user already exists")
	} else if err := Sh("useradd --system --create-home --shell /bin/bash " + StewardUser); err != nil {
		return err
	}
	// A real login shell is required, not nologin: scoped SSH authenticates as this user
	// and sshd runs the forced command via the user's login shell (`bash -c "steward …"`),
	// so nologin would refuse every scoped invocation. Idempotent — also fixes a user
	// created by an older prepare. The forced command + key restrictions are the boundary,
	// not the shell.
	if err := Sh("usermod --shell /bin/bash " + StewardUser); err != nil {
		return err
	}
	// Subuid/subgid ranges let rootless Podman map container users.
	if err := Sh(`
grep -q '^steward:' /etc/subuid || echo 'steward:100000:65536' >> /etc/subuid
grep -q '^steward:' /etc/subgid || echo 'steward:100000:65536' >> /etc/subgid
`); err != nil {
		return err
	}
	// Linger lets the steward user's services run without an active login.
	return Sh("loginctl enable-linger " + StewardUser)
}

func ensureFloor() error {
	// The record lives at the path audit.go defaults to. Append-only (chattr +a)
	// so even root can only add to it, never edit or truncate.
	//
	// Idempotent, and the +a attribute is the "already provisioned" signal: once
	// the record is append-only, chown/chmod on it are themselves refused, so we
	// must skip them on re-run. (The record file already exists by now — dispatch
	// wrote this prepare's own entry before this step ran.)
	return Sh(fmt.Sprintf(`
set -euo pipefail
dir=/var/lib/steward
rec="$dir/record.log"
mkdir -p "$dir"
chown %[1]s:%[1]s "$dir"
chmod 0750 "$dir"
if lsattr "$rec" 2>/dev/null | awk '{print $1}' | grep -q a; then
  echo "record already append-only; nothing to do"
else
  [ -e "$rec" ] || touch "$rec"
  chown %[1]s:%[1]s "$rec"
  chmod 0640 "$rec"
  chattr +a "$rec"
  echo "record secured (append-only) at $rec"
fi
`, StewardUser))
}

// ensureSnapshotTimer makes the box record itself: a systemd timer runs
// `steward snapshot` on a cadence (the daemonless recording-residency answer —
// no resident daemon, systemd provides the heartbeat). Runs as the steward user so
// `podman ps` sees the rootless app containers; linger keeps /run/user/<uid> alive
// across boots, and Steward's exec seam supplies XDG_RUNTIME_DIR.
func ensureSnapshotTimer() error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	service := fmt.Sprintf(`[Unit]
Description=Steward status snapshot
After=network.target

[Service]
Type=oneshot
User=%s
ExecStart=%s snapshot
`, StewardUser, self)
	timer := `[Unit]
Description=Run steward snapshot on a cadence

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
`
	if err := os.WriteFile(SnapshotServicePath, []byte(service), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(snapshotTimerPath, []byte(timer), 0o644); err != nil {
		return err
	}
	return Sh("systemctl daemon-reload && systemctl enable --now steward-snapshot.timer")
}

// --- prepare UX ---

// hasFlag reports whether args carries any of these boolean flags.
//
// Exact match, and it can afford to be: the gate refuses a boolean given a value
// (booleanWithValue) before a command ever runs, so `--yes=1` never arrives here.
// Reading it here instead would mean deciding what `--yes=false` means, and the only
// honest answers are "no" — which is not what the flag's presence says — or a lie.
func hasFlag(args []string, names ...string) bool {
	for _, a := range args {
		for _, n := range names {
			if a == n {
				return true
			}
		}
	}
	return false
}

// confirmInstall mirrors apt's "you are about to install X" courtesy. Returns true
// to proceed. --yes skips it; a non-terminal without --yes declines (so automation
// must pass --yes). When nothing needs installing, it proceeds silently.
func confirmInstall(sub Substrate, yes bool) bool {
	if yes {
		return true
	}
	if len(sub.Packages) == 0 && sub.Note == "" {
		return true // this role wants nothing
	}
	out, err := exec.Command("apt-get", append([]string{"install", "-s"}, sub.Packages...)...).Output() // #nosec G204 -- the packages the app layer declares, not caller input
	s := string(out)
	if err == nil && strings.Contains(s, "0 upgraded, 0 newly installed") && sub.Note == "" {
		return true // nothing to install
	}

	note := ""
	if sub.Note != "" {
		note = " (" + sub.Note + ")"
	}
	fmt.Printf("\nAbout to install: %s%s\n", strings.Join(sub.Packages, " "), note)
	for _, ln := range strings.Split(s, "\n") {
		t := strings.TrimSpace(ln)
		if strings.HasPrefix(t, "Need to get") || strings.Contains(t, "After this operation") {
			fmt.Println("  " + t)
		}
	}
	return confirm("Continue? [Y/n] ", true)
}

// confirm asks a y/n question at the terminal; defaultYes sets what bare Enter
// means. A non-terminal declines, so automation must pass --yes.
func confirm(prompt string, defaultYes bool) bool {
	if !isTTY() {
		fmt.Println("Not a terminal — re-run with --yes to proceed non-interactively.")
		return false
	}
	fmt.Print(prompt)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	line = strings.ToLower(strings.TrimSpace(line))
	if line == "" {
		return defaultYes
	}
	return line == "y" || line == "yes"
}

func isTTY() bool {
	fi, err := os.Stdin.Stat()
	return err == nil && (fi.Mode()&os.ModeCharDevice) != 0
}

func printPrepareSummary() {
	rule := "────────────────────────────────────────────"
	fmt.Printf("\n%s\n  Box prepared — %s\n%s\n", rule, osPretty(), rule)
	// No substrate versions here. The app layer prints its own as it installs them:
	// running `podman --version` from the ceiling would put the app layer's
	// dependency back in the core, in the one place nobody would think to look.
	fmt.Printf("  Record:    /var/lib/steward/record.log (append-only)\n")
	fmt.Printf("  Snapshot:  timer active (records on a cadence)\n")
	fmt.Printf("\n  Everything past here runs as the 'steward' user. Drop in once:\n")
	fmt.Printf("    sudo -iu steward\n")
	fmt.Printf("  then, plainly:\n")
	fmt.Printf("    steward doctor\n")
	fmt.Printf("    steward authorize <pubkey> --client <name> --scope operate\n\n")
}

// osPretty reads PRETTY_NAME from /etc/os-release (shared with harden.go).
func osPretty() string {
	b, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "Linux"
	}
	for _, ln := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(ln, "PRETTY_NAME=") {
			return strings.Trim(strings.TrimPrefix(ln, "PRETTY_NAME="), `"`)
		}
	}
	return "Linux"
}

func CmdFirstLine(name string, args ...string) string {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		return "?"
	}
	s := strings.TrimSpace(string(out))
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[:i]
	}
	return s
}

// --- helpers ---

func Have(tool string) bool {
	_, err := exec.LookPath(tool)
	return err == nil
}

// Sh runs a bash script, streaming output, with non-interactive apt.
func Sh(script string) error {
	c := exec.Command("bash", "-c", script)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	c.Env = append(os.Environ(), "DEBIAN_FRONTEND=noninteractive")
	return c.Run()
}

// roleFromArgs reads the role off the command line. A box exists to do something, and
// saying which costs one word — bare `prepare` is refused rather than defaulted, because
// a defaulted role is an inference nobody stated and this box's purpose is a fact its
// record should carry.
// The role is the *first* argument, deliberately, and not merely the first positional:
// ParseArgs consumes the token after a flag as that flag's value, so `prepare --yes host`
// would quietly swallow the role and prepare nothing. Requiring it first makes the parse
// unambiguous and matches the synopsis.
func roleFromArgs(args []string) (string, error) {
	if len(args) == 0 || args[0] == "" {
		return "", fmt.Errorf("say what this box is for: %s", strings.Join(Roles, " or "))
	}
	if strings.HasPrefix(args[0], "-") {
		return "", fmt.Errorf("the role comes first: steward prepare <%s> [--yes]", strings.Join(Roles, "|"))
	}
	if !ValidRole(args[0]) {
		return "", fmt.Errorf("unknown role %q — expected %s", args[0], strings.Join(Roles, " or "))
	}
	return args[0], nil
}

// recordRole writes what this box was prepared as into the chain, so "what is this
// machine for, who said so, and when" is answerable from the record rather than inferred
// from what happens to be installed.
//
// It runs *after* ensureFloor, and it has to: on a first prepare the record does not
// exist until the floor lays it, so this is the earliest point at which anything can be
// recorded at all. The role file is written earlier — before any install — so a mistyped
// conversion is refused before it costs anything; this entry is the history of that fact,
// not the fact itself.
func recordRole(role string) error {
	return Record(ActorName(), string(ScopeRoot), "prepare-role", []string{role})
}

// openRolePorts opens the ports this role serves on, if there is a firewall to open
// them in.
//
// It deliberately does **not** install or enable UFW. `harden` is optional and
// `prepare` is required, so making prepare depend on a firewall would quietly make
// hardening mandatory and break the property that a box is fully accountable without
// it. An unhardened box has no firewall to open a hole in, and that is fine.
//
// Both current roles serve web, but the ports are chosen *by role* so a future role
// that serves nothing can decline them without this becoming a special case.
func openRolePorts(role string) error {
	ports := rolePorts(role)
	if len(ports) == 0 {
		fmt.Println("this role serves no ports")
		return nil
	}
	if !Have("ufw") {
		fmt.Println("no ufw on this box (not hardened) — nothing to open")
		return nil
	}
	if out, err := exec.Command("ufw", "status").Output(); err != nil || !strings.Contains(string(out), "Status: active") {
		fmt.Println("ufw is not active (not hardened) — nothing to open")
		return nil
	}
	for _, p := range ports {
		if err := Sh(fmt.Sprintf("ufw allow %d/tcp", p)); err != nil {
			return fmt.Errorf("ufw allow %d: %w", p, err)
		}
		fmt.Printf("ufw allows %d\n", p)
	}
	return nil
}

// rolePorts is what a role listens on publicly. Both roles terminate HTTP(S) today.
func rolePorts(role string) []int {
	switch role {
	case RoleHost, RoleBalancer:
		return []int{80, 443}
	}
	return nil
}
