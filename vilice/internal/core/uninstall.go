package core

// `uninstall` (root-only ceiling): the inverse of `prepare` — remove the gate and
// the scribe, never the runtime. Apps are ordinary Quadlet units under systemd with
// plain Caddy routes, so they keep running unless the operator chooses otherwise
// here. What stays: the _vilice user and /var/lib/vilice — the record is the box's
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

	items, err := appInventory()
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}

	// Decide the apps' fate first, act only after the one Proceed confirm below —
	// a declined confirm must mean nothing happened.
	if len(items) > 0 && !removeApps && !yes {
		fmt.Printf("\n%d app(s) on this box: %s\n", len(items), strings.Join(items, ", "))
		fmt.Println("Kept, they run on as ordinary systemd services behind Caddy — no vilice needed.")
		removeApps = confirm("Remove them too? [y/N] ", false)
	}

	printUninstallPlan(items, removeApps)

	if !yes && !confirm("\nProceed? [y/N] ", false) {
		return Result{Code: "aborted", Message: "uninstall cancelled — nothing removed"}
	}

	if removeApps {
		if err := removeAppsAsVilice(items); err != nil {
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
		{"remove binary authorization", removeBinaryDigest},
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
	// The plan above already listed what stays, the app layer's substrate included;
	// this is the recap of what vilice itself left, which is all the ceiling knows.
	return OK(fmt.Sprintf(`vilice removed. Still here:%s
  - the _vilice user and /var/lib/vilice — the record is the box's history
  - whatever prepare installed to run apps — uninstall removes no packages
Retiring the hardware entirely? Wipe /var/lib/vilice/secrets and remove the
_vilice user — see the Uninstall notes in the docs.`, kept))
}

// appInventory is what the app layer has placed on this box. The ceiling needs the
// names to tell an operator what uninstall is about to affect; it never needs to
// know what any of them are.
func appInventory() ([]string, error) {
	if apps == nil {
		return nil, nil
	}
	return apps.Inventory()
}

func printUninstallPlan(items []string, removeApps bool) {
	fmt.Println("\nThis removes:")
	if removeApps && len(items) > 0 {
		fmt.Printf("  - %d app(s): containers, routes, quadlet units (%s)\n",
			len(items), strings.Join(items, ", "))
	}
	fmt.Println("  - the snapshot timer (vilice-snapshot.timer)")
	fmt.Println("  - every scoped key (the authorized_keys ledger — Vilice Console loses access)")
	fmt.Println("  - the OS-update grant (/etc/sudoers.d/vilice)")
	fmt.Println("  - the binary authorization (" + BinaryDigestPath() + ")")
	fmt.Println("  - this binary")
	fmt.Println("\nThis keeps:")
	if !removeApps && len(items) > 0 {
		fmt.Printf("  - %d app(s), running on as ordinary systemd services behind Caddy\n", len(items))
	}
	fmt.Println("  - the _vilice user and /var/lib/vilice — the record is the box's history")
	// What else stays is the app layer's to say: it installed it, it knows what this
	// box's role got, and the ceiling naming a fixed set told a balancer it was
	// keeping tools it never had.
	if apps != nil {
		apps.TeardownNote(os.Stdout)
	}
}

// removeAppsAsVilice tears each app down through vilice's own remove, run as the
// _vilice user (running it as root would touch root's Podman world — the exact
// ghost-state mistake the wrong_user gate exists to refuse).
func removeAppsAsVilice(names []string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	for _, name := range names {
		fmt.Printf("\n=== remove %s ===\n", name)
		c := exec.Command("sudo", "-u", ViliceUser, self, "remove", name) // #nosec G204 -- self is this binary; names come from vilice's own state dir
		c.Stdout, c.Stderr = os.Stdout, os.Stderr
		if err := c.Run(); err != nil {
			return fmt.Errorf("remove %s: %w", name, err)
		}
	}
	return nil
}

func removeSnapshotTimer() error {
	_ = Sh("systemctl disable --now vilice-snapshot.timer") // absent is fine
	for _, p := range []string{snapshotTimerPath, SnapshotServicePath} {
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			return err
		}
	}
	return Sh("systemctl daemon-reload")
}

// removeLedger deletes the _vilice user's authorized_keys — every scoped grant at
// once. The user and home stay; only the rights ledger goes.
func removeLedger() error {
	u, err := user.Lookup(ViliceUser)
	if err != nil {
		return nil // no _vilice user, no ledger
	}
	p := filepath.Join(u.HomeDir, ".ssh", "authorized_keys")
	if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

// removeBinaryDigest withdraws the authorization prepare granted. A binary left
// behind by hand is then a binary nothing has authorized, and every verb that acts
// refuses — the same reason the ledger, not the key files, is what revoke removes.
func removeBinaryDigest() error {
	if err := os.Remove(BinaryDigestPath()); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func removeUpdatePrivilege() error {
	if err := os.Remove("/etc/sudoers.d/vilice"); err != nil && !os.IsNotExist(err) {
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
