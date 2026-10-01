package core

import (
	"os"
	"os/exec"
)

// `apply-updates` (operate): apply machine OS package updates on demand — the
// deliberate, full upgrade. Automatic *security* patches are a separate, hands-off
// concern (harden's unattended-upgrades).
//
// apt needs root, but apply-updates is operate-scoped and so runs as the
// unprivileged _vilice user (ceiling-is-the-machine). It escalates through the one
// narrow sudoers grant `prepare` lays — exactly the two commands below, nothing
// else — so the ceiling stays small and legible (see provision.go sudoersForUpdates).
func applyUpdatesCmd(args []string) Result {
	for _, cmd := range aptUpdateCommands() {
		if err := runAsRoot(cmd); err != nil {
			return Result{Code: "update_failed", Retryable: true, Message: err.Error()}
		}
	}
	return OK("machine packages updated")
}

// aptUpdateCommands is the fixed list apply-updates runs. It must stay in lockstep
// with the sudoers grant (provision.go) — a test cross-checks the two.
func aptUpdateCommands() [][]string {
	return [][]string{
		{"apt-get", "update", "-y"},
		{"apt-get", "upgrade", "-y"},
	}
}

// sudoize prefixes a fixed argv with non-interactive sudo unless already root. The
// argv is never altered otherwise, so it matches the sudoers rule exactly.
func sudoize(euid int, argv []string) []string {
	if euid == 0 {
		return argv
	}
	return append([]string{"sudo", "-n"}, argv...)
}

// runAsRoot runs a command as root: directly when already root, else through the
// _vilice user's narrow sudo grant.
func runAsRoot(argv []string) error {
	argv = sudoize(os.Geteuid(), argv)
	// #nosec G204 -- argv is never caller input: it comes from aptUpdateCommands()'s
	// fixed list, and sudoize only prefixes `sudo -n`. A test cross-checks that list
	// against the sudoers grant, so the two cannot drift apart.
	c := exec.Command(argv[0], argv[1:]...)
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	c.Env = append(os.Environ(), "DEBIAN_FRONTEND=noninteractive")
	return c.Run()
}
