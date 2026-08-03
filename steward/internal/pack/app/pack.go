package app

import (
	"fmt"
	"io"
	"os"

	"steward/internal/core"
)

// Pack is the founding verb pack: running apps on the box and keeping them
// running. It is named for what it promises — apps deployed, routed, and
// recoverable — not for Podman, Caddy, or restic, which are today's substrate
// and may not be tomorrow's. See decisions/core-and-packs.md.
//
// It holds no privilege the core does not hand it. Every verb below arrives
// through the core's single door, with the account gate applied and the record
// written, before any of this code runs.
type Pack struct{}

// New returns the app pack, ready to register.
func New() Pack { return Pack{} }

// Name is the pack's name in the manifest and in the record.
func (Pack) Name() string { return "steward-app" }

// Verbs are the commands this pack contributes. Order within a scope is the
// order `steward help` shows them in.
//
// Fields are named, not positional: a pack is compiled against a core it does not
// own, and an unkeyed literal would rebind silently the day Command grows a field.
func (Pack) Verbs() []core.Command {
	return []core.Command{
		// Deploy & lifecycle — operate.
		{Name: "deploy", Scope: core.ScopeOperate,
			Summary: "Deploy an app from a digest-pinned image (health-check, then flip)",
			Usage:   "<app> --image <ref> [--port <n>] [--hostname <host>] [--health <path>]\n  steward deploy <app> < spec.json   (full spec: env, secrets, volumes)",
			Flags:   []string{"image", "port", "hostname", "health"}, Run: deployCmd},
		{Name: "rollback", Scope: core.ScopeOperate, Summary: "Re-deploy the last-good image",
			Usage: "<app>", Run: rollbackCmd},
		{Name: "start", Scope: core.ScopeOperate, Summary: "Start an app", Usage: "<app>", Run: startCmd},
		{Name: "stop", Scope: core.ScopeOperate, Summary: "Stop an app", Usage: "<app>", Run: stopCmd},
		{Name: "restart", Scope: core.ScopeOperate, Summary: "Restart an app", Usage: "<app>", Run: restartCmd},
		{Name: "remove", Scope: core.ScopeOperate, Summary: "Take an app off the box", Usage: "<app>", Run: removeCmd},
		{Name: "backup", Scope: core.ScopeOperate, Summary: "Snapshot an app (or --all, or --machine)",
			Usage: "<app> | --all | --machine | --repo <url>  (repo password on stdin)",
			Flags: []string{"all", "machine", "repo"}, Run: backupCmd},
		{Name: "restore", Scope: core.ScopeOperate,
			Summary: "Restore an app from its latest snapshot (or --machine)",
			Usage:   "<app> [--snapshot <id>] | --machine",
			Flags:   []string{"machine", "snapshot"}, Run: restoreCmd},
		{Name: "registry-login", Scope: core.ScopeOperate,
			Summary: "Log the box into a private image registry (password on stdin)",
			Usage:   "<registry> --username <name>  (password on stdin)",
			Flags:   []string{"username"}, Run: registryLoginCmd},
		{Name: "registry-logout", Scope: core.ScopeOperate,
			Summary: "Remove the box's login for a registry",
			Usage:   "<registry>", Run: registryLogoutCmd},

		// Observe.
		{Name: "status", Scope: core.ScopeObserve,
			Summary: "Machine summary plus installed apps and their state", Run: statusCmd},
		{Name: "logs", Scope: core.ScopeObserve, Summary: "Tail an app's logs",
			Usage: "<app> [--tail <n>]", Flags: []string{"tail"}, Run: logsCmd},
		{Name: "doctor", Scope: core.ScopeObserve,
			Summary: "Check prerequisites and surface problems", Run: doctorCmd},

		// The status time-series, on the systemd timer.
		{Name: "snapshot", Scope: core.ScopeSystem,
			Summary: "Write one record point (systemd-timer invoked)", Run: snapshotCmd},
	}
}

// Inventory is the apps this pack has placed on the box, by name — what the
// ceiling needs to tell an operator what `uninstall` will affect.
func (Pack) Inventory() ([]string, error) {
	apps, err := listApps()
	if err != nil {
		return nil, err
	}
	names := make([]string, len(apps))
	for i, a := range apps {
		names[i] = a.Name
	}
	return names, nil
}

// TeardownNote surfaces the restic repo at the last moment the box can: the repo
// and its snapshots outlive the box, and without the password every backup is
// unreadable ciphertext.
//
// It prints *where* the password is, never the password. Uninstall keeps
// /var/lib/steward, so the file is still on the box for the operator who needs it —
// printing the secret itself bought nothing and spent it into terminal scrollback,
// the systemd journal, and the log of any automation that ran `uninstall --yes`. One
// more command for the person who needs it; nobody else ends up holding it.
func (Pack) TeardownNote(w io.Writer) {
	cfg, ok := loadBackupConfig()
	if !ok {
		return
	}
	fmt.Fprintf(w, "\nBackups: restic repo %s\n", cfg.Repo)
	if _, err := os.Stat(resticPasswordFile()); err != nil {
		fmt.Fprintln(w, "  No password file on this box — if the repo matters, find its password")
		fmt.Fprintln(w, "  before wiping anything, or the snapshots are unreadable ciphertext.")
		return
	}
	fmt.Fprintln(w, "  The repo and its snapshots outlive this box, and without the password every")
	fmt.Fprintln(w, "  backup is unreadable. Copy it somewhere safe now:")
	fmt.Fprintf(w, "    sudo cat %s\n", resticPasswordFile())
	fmt.Fprintf(w, "  It stays readable on this box until you wipe %s.\n", secretsDir())
}
