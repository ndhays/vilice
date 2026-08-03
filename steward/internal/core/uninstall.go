package core

// `uninstall` (root-only ceiling): the inverse of `prepare` — remove the gate and
// the scribe, never the runtime. Apps are ordinary Quadlet units under systemd with
// plain Caddy routes, so they keep running unless the operator chooses otherwise
// here. What stays: the steward user and /var/lib/steward — the record is the box's
// history and outlives the tool. See decisions/uninstall-removes-the-gate.md.

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strings"
)

func uninstallCmd(args []string) Result {
	if os.Geteuid() != 0 {
		return Result{Code: "not_root",
			Message: "uninstall must run as root (it removes the root-owned files prepare created)"}
	}
	yes := hasFlag(args, "-y", "--yes")
	removeApps := hasFlag(args, "--remove-apps")

	fmt.Println("Uninstall removes the gate and the scribe — the record stops; nothing running does.")

	items, err := packInventory()
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}

	// Decide the apps' fate first, act only after the one Proceed confirm below —
	// a declined confirm must mean nothing happened.
	if len(items) > 0 && !removeApps && !yes {
		fmt.Printf("\n%d app(s) on this box: %s\n", len(items), strings.Join(items, ", "))
		fmt.Println("Kept, they run on as ordinary systemd services behind Caddy — no steward needed.")
		removeApps = confirm("Remove them too? [y/N] ", false)
	}

	for _, p := range Packs() {
		p.TeardownNote(os.Stdout)
	}
	printUninstallPlan(items, removeApps)

	if !yes && !confirm("\nProceed? [y/N] ", false) {
		return Result{Code: "aborted", Message: "uninstall cancelled — nothing removed"}
	}

	if removeApps {
		if err := removeAppsAsSteward(items); err != nil {
			return Result{Code: "uninstall_failed", Retryable: true, Message: err.Error()}
		}
	}
	steps := []struct {
		name string
		fn   func() error
	}{
		{"remove snapshot timer", removeSnapshotTimer},
		{"remove scoped keys", removeLedger},
		{"remove OS-update grant", removeUpdatePrivilege},
		{"remove pack authorization", removePackManifest},
		{"remove binary", removeBinary},
	}
	for _, s := range steps {
		fmt.Printf("\n=== %s ===\n", s.name)
		if err := s.fn(); err != nil {
			return Result{Code: "uninstall_failed", Retryable: true, Message: fmt.Sprintf("%s: %v", s.name, err)}
		}
	}

	kept := ""
	if len(items) > 0 && !removeApps {
		kept = fmt.Sprintf("\n  - %d app(s) still running — ordinary systemd services behind Caddy", len(items))
	}
	return OK(fmt.Sprintf(`steward removed. Still here:%s
  - the steward user and /var/lib/steward — the record is the box's history
  - podman, caddy, restic
Retiring the hardware entirely? Wipe /var/lib/steward/secrets and remove the
steward user — see the Uninstall notes in the docs.`, kept))
}

// packInventory is what the registered packs have placed on this box. The ceiling
// needs the names to tell an operator what uninstall is about to affect; it never
// needs to know what any of them are.
func packInventory() ([]string, error) {
	var all []string
	for _, p := range Packs() {
		items, err := p.Inventory()
		if err != nil {
			return nil, err
		}
		all = append(all, items...)
	}
	return all, nil
}

func printUninstallPlan(items []string, removeApps bool) {
	fmt.Println("\nThis removes:")
	if removeApps && len(items) > 0 {
		fmt.Printf("  - %d app(s): containers, routes, quadlet units (%s)\n",
			len(items), strings.Join(items, ", "))
	}
	fmt.Println("  - the snapshot timer (steward-snapshot.timer)")
	fmt.Println("  - every scoped key (the authorized_keys ledger — Steward Console loses access)")
	fmt.Println("  - the OS-update grant (/etc/sudoers.d/steward)")
	fmt.Println("  - the pack authorization (" + PackManifestPath() + ")")
	fmt.Println("  - this binary")
	fmt.Println("\nThis keeps:")
	if !removeApps && len(items) > 0 {
		fmt.Printf("  - %d app(s), running on as ordinary systemd services behind Caddy\n", len(items))
	}
	fmt.Println("  - the steward user and /var/lib/steward — the record is the box's history")
	fmt.Println("  - podman, caddy, restic")
}

// removeAppsAsSteward tears each app down through steward's own remove, run as the
// steward user (running it as root would touch root's Podman world — the exact
// ghost-state mistake the wrong_user gate exists to refuse).
func removeAppsAsSteward(names []string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	for _, name := range names {
		fmt.Printf("\n=== remove %s ===\n", name)
		c := exec.Command("sudo", "-u", StewardUser, self, "remove", name) // #nosec G204 -- self is this binary; names come from steward's own state dir
		c.Stdout, c.Stderr = os.Stdout, os.Stderr
		if err := c.Run(); err != nil {
			return fmt.Errorf("remove %s: %w", name, err)
		}
	}
	return nil
}

func removeSnapshotTimer() error {
	_ = Sh("systemctl disable --now steward-snapshot.timer") // absent is fine
	for _, p := range []string{snapshotTimerPath, SnapshotServicePath} {
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return Sh("systemctl daemon-reload")
}

// removeLedger deletes the steward user's authorized_keys — every scoped grant at
// once. The user and home stay; only the rights ledger goes.
func removeLedger() error {
	u, err := user.Lookup(StewardUser)
	if err != nil {
		return nil // no steward user, no ledger
	}
	p := filepath.Join(u.HomeDir, ".ssh", "authorized_keys")
	if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// removePackManifest withdraws the authorization prepare granted. The shelf itself is
// left alone: an empty directory is harmless, and anything an operator put there is
// theirs. Without the manifest nothing on it may run, which is the property that
// matters — the same reason the ledger, not the key files, is what revoke removes.
func removePackManifest() error {
	if err := os.Remove(PackManifestPath()); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func removeUpdatePrivilege() error {
	if err := os.Remove("/etc/sudoers.d/steward"); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func removeBinary() error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	return os.Remove(self)
}
