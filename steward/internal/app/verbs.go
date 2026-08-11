package app

import (
	"fmt"
	"io"
	"os"
	"strings"

	"steward/internal/core"
)

// Layer is the app layer: running apps on the box and keeping them running. It is
// named for what it promises — apps deployed, routed, and recoverable — not for
// Podman, Caddy, or restic, which are today's substrate and may not be tomorrow's.
//
// It is the far side of the one line drawn inside this binary
// (decisions/roles-not-packs.md), and it holds no privilege the core does not hand
// it. Every verb below arrives through the core's single door, with the account
// gate applied and the record written, before any of this code runs.
type Layer struct{}

// New returns the app layer, ready to register.
func New() Layer { return Layer{} }

// Verbs are the commands this layer contributes. Order within a scope is the
// order `steward help` shows them in.
//
// Fields are named, not positional: an unkeyed literal would rebind silently the
// day core.Command grows a field.
func (Layer) Verbs() []core.Command {
	return []core.Command{
		// Deploy & lifecycle — operate.
		{Name: "deploy", Scope: core.ScopeOperate,
			Summary: "Deploy an app from a digest-pinned image",
			Long: `Brings up the new container alongside the one already serving, polls it
until it answers healthy, and only then moves traffic across. If it
never answers, the old app is left running and the deploy fails — a
bad image costs you an error message, not an outage.

The image that was serving is remembered as last-good, so steward
rollback is always available.

Images are digest-pinned (ref@sha256:…). A tag is refused, because a
tag is not a thing you can redeploy: it means something different
tomorrow, and "the image that was running" has to be an answer.

The flags cover the common app. Anything with env, secrets, or volumes
sends a full spec on stdin instead — that spec is the desired state
and it replaces the old one wholesale, so what you send is what runs.`,
			Usage: "<app> --image <ref> [--port <n>] [--hostname <host>]\n  steward deploy <app> < spec.json   (full spec: env, secrets, volumes)",
			Flags: []core.Flag{
				{Name: "image", Arg: "<ref>", What: "The image to run, pinned by digest: ref@sha256:… Required."},
				{Name: "port", Arg: "<n>", What: "Port the app listens on inside the container. Default 8080."},
				{Name: "hostname", Arg: "<host>", What: "Public hostname Caddy routes to this app."},
				{Name: "health", Arg: "<path>", What: "Path polled until it answers 200. Default /."},
			},
			Examples: []core.Example{
				{Cmd: "steward deploy blog --image ghcr.io/me/blog@sha256:ab12… \\\n    --hostname blog.example.com", What: "Deploy and route a straightforward web app."},
				{Cmd: "steward deploy blog < blog.json", What: "Deploy the full spec: env, secrets, volumes, backup hook."},
			},
			Run: deployCmd},
		{Name: "rollback", Scope: core.ScopeOperate, Summary: "Re-deploy the last-good image",
			Long: `Re-deploys the image that was serving before the current one, through
the same health-check-then-flip path as any other deploy.

Last-good is one image deep, not a history. It is the answer to "put
back what was working a minute ago", which is the question you have at
the moment you need it. Anything older is a deploy of that digest.`,
			Usage: "<app>",
			Examples: []core.Example{
				{Cmd: "steward rollback blog", What: "Put the previous image back."},
			},
			Run: rollbackCmd},
		{Name: "start", Scope: core.ScopeOperate, Summary: "Start an app",
			Long: `Starts the app's systemd unit. Its spec is unchanged — this is the
lifecycle switch, not a deploy.`,
			Usage: "<app>",
			Examples: []core.Example{
				{Cmd: "steward start blog", What: "Bring a stopped app back up."},
			},
			Run: startCmd},
		{Name: "stop", Scope: core.ScopeOperate, Summary: "Stop an app",
			Long: `Stops the app's systemd unit. The spec, the data, and the route stay
where they are, so start brings back the same app. To take it off the
box entirely, use remove.`,
			Usage: "<app>",
			Examples: []core.Example{
				{Cmd: "steward stop blog", What: "Take an app out of service without removing it."},
			},
			Run: stopCmd},
		{Name: "restart", Scope: core.ScopeOperate, Summary: "Restart an app",
			Long: `Restarts the app's systemd unit on the same image and spec. There is
no health-check flip here — that is what deploy is for.`,
			Usage: "<app>",
			Examples: []core.Example{
				{Cmd: "steward restart blog", What: "Bounce an app in place."},
			},
			Run: restartCmd},
		{Name: "remove", Scope: core.ScopeOperate, Summary: "Take an app off the box",
			Long: `Removes the app: its unit, its spec, and its Caddy route. The record
of everything it did stays, and so do its backups — those live in the
restic repo, not on this box.`,
			Usage: "<app>",
			Examples: []core.Example{
				{Cmd: "steward remove blog", What: "Retire an app from this machine."},
			},
			Run: removeCmd},
		// The edge half: this box fronting *other* boxes. Declarative and wholly
		// replaced, like deploy — you send the table the box should serve. See route.go.
		{Name: "route", Scope: core.ScopeOperate,
			Summary: "Front other boxes: replace the routing table",
			Long: `Replaces this box's routing table with the one you send on stdin: the
hostnames this box fronts for *other* boxes, and where each one goes.

This is what a balancer is for. It works on a host too — the routing
table is a separate Caddy fragment from the one deploy writes, so the
two never touch — but a box that fronts others and runs nothing itself
is the case this exists to serve.

Declarative and whole, like deploy. You send the table the box should
serve, not an edit to the table it has — so what is in the file is
what is routed, and there is no accumulated state to reason about.

  {"routes": [{"hostnames": ["app.example.com"],
               "upstreams": ["10.0.0.5:8080"]}]}`,
			Usage: "< table.json",
			Examples: []core.Example{
				{Cmd: "steward route < edge.json", What: "Serve exactly the routes in edge.json, and no others."},
			},
			Run: routeCmd},
		{Name: "backup", Scope: core.ScopeOperate, Summary: "Snapshot an app (or --all, or --machine)",
			Long: `Snapshots an app's declared volumes together with its spec, so what
comes back is self-contained: the data, and how to redeploy it.

Backups go to a restic repo you own. restic encrypts on this box with
your key, so the destination only ever sees ciphertext and can live on
infrastructure you do not trust.

Configure the repo once with --repo; the password is read on stdin and
written to a 0600 file, never passed on argv where it would land in
the record and the process table.

Steward stays database-agnostic. An app that needs a consistent dump
declares a backup hook in its spec; Steward never learns what Postgres
or SQLite is.`,
			Usage: "<app> | --all | --machine | --repo <url>",
			Flags: []core.Flag{
				{Name: "all", What: "Snapshot every app on the box."},
				{Name: "machine", What: "Snapshot Steward's own record off-box."},
				{Name: "repo", Arg: "<url>", What: "One-time setup: set the restic repo, read its password on stdin, and initialise it."},
			},
			Examples: []core.Example{
				{Cmd: "steward backup --repo s3:s3.example.com/steward < repo.pass", What: "Point the box at a repo. Do this once, before anything else."},
				{Cmd: "steward backup blog", What: "Snapshot one app's volumes and spec."},
				{Cmd: "steward backup --all", What: "Snapshot every app on the box."},
			},
			Run: backupCmd},
		{Name: "restore", Scope: core.ScopeOperate,
			Summary: "Restore an app from its latest snapshot (or --machine)",
			Long: `Puts an app's data and spec back from the latest snapshot, then
redeploys it.

A restore writes into the live filesystem, so what the repo is allowed
to write is a boundary, not a detail: only this app's spec and its
declared volumes are extracted. Nothing else in the snapshot is, even
if the snapshot contains it.`,
			Usage: "<app> [--snapshot <id>] | --machine",
			Flags: []core.Flag{
				{Name: "machine", What: "Restore Steward's own record instead of an app."},
				{Name: "snapshot", Arg: "<id>", What: "Restore this snapshot rather than the latest."},
			},
			Examples: []core.Example{
				{Cmd: "steward restore blog", What: "Put the app back as of its last snapshot, and redeploy."},
				{Cmd: "steward restore blog --snapshot 4f8c1a2b", What: "Go back to a particular snapshot."},
			},
			Run: restoreCmd},
		{Name: "registry-login", Scope: core.ScopeOperate,
			Summary: "Log the box into a private image registry",
			Long: `Logs the box into a private registry so later pulls can reach it.

This is a box credential, not part of any app: one persistent rootless
login, shared by every app and surviving reboots. The password is read
on stdin and never appears on argv — only the registry and the
username reach the record.

A pull from a registry the box is not logged into fails loudly and
safely: the running app is untouched, and the error points back here.

Static credentials only — a token, a password, an htpasswd entry.
Registries that hand out short-lived tokens (ECR, GCP) want a
credential helper, which is not supported yet.`,
			Usage: "<registry> --username <name>  (password on stdin)",
			Flags: []core.Flag{
				{Name: "username", Arg: "<name>", What: "The registry username. Recorded; the password is not."},
			},
			Examples: []core.Example{
				{Cmd: "steward registry-login ghcr.io --username me < token.txt", What: "Log in with a personal access token from a file."},
			},
			Run: registryLoginCmd},
		{Name: "registry-logout", Scope: core.ScopeOperate,
			Summary: "Remove the box's login for a registry",
			Long: `Removes the box's stored login for that registry. Apps already running
keep running — this affects the next pull, not the current container.`,
			Usage: "<registry>",
			Examples: []core.Example{
				{Cmd: "steward registry-logout ghcr.io", What: "Withdraw the box's registry credential."},
			},
			Run: registryLogoutCmd},

		// Observe.
		{Name: "status", Scope: core.ScopeObserve,
			Summary: "Machine summary plus installed apps and their state",
			Long: `Summarises the machine — role, disk, load, hardening posture — and
lists every app with its image, route, and whether it is up.

A read: it changes nothing and is not recorded. This is what the
console polls, and what you type when you want to know where things
stand.`,
			Examples: []core.Example{
				{Cmd: "steward status", What: "See what this box is and what is running on it."},
				{Cmd: "steward status --json", What: "The same, structured, for a program to read."},
			},
			Run: statusCmd},
		{Name: "logs", Scope: core.ScopeObserve, Summary: "Tail an app's logs",
			Long: `Prints the running container's logs. A passthrough — the container is
the source of truth, so Steward stores nothing and shows you what is
actually there.`,
			Usage: "<app> [--tail <n>]",
			Flags: []core.Flag{
				{Name: "tail", Alias: "n", Arg: "<n>", What: "Show only the last n lines. Default: everything."},
			},
			Examples: []core.Example{
				{Cmd: "steward logs blog --tail 100", What: "The last hundred lines."},
			},
			Run: logsCmd},
		{Name: "doctor", Scope: core.ScopeObserve,
			Summary: "Check prerequisites and surface problems",
			Long: `Checks the box over and reports what is wrong: the tools Steward
drives, the record floor, ghost containers left by a wrong-user run,
and whether the binary still sits where the scoped keys expect it.

It reports; it does not repair. Run it after an upgrade, after moving
anything, or when something is behaving oddly.`,
			Examples: []core.Example{
				{Cmd: "steward doctor", What: "Ask the box what is wrong with it."},
			},
			Run: doctorCmd},

		// The status time-series, on the systemd timer.
		{Name: "snapshot", Scope: core.ScopeSystem,
			Summary: "Write one record point (systemd-timer invoked)",
			Long: `Writes one status point to the record. systemd's timer calls this;
it is not a command you type.

It is what gives the record a heartbeat without a resident daemon —
systemd provides the residency, Steward provides the entry.`,
			Run: snapshotCmd},
	}
}

// Inventory is the apps this layer has placed on the box, by name — what the
// ceiling needs to tell an operator what `uninstall` will affect.
func (Layer) Inventory() ([]string, error) {
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

// TeardownNote names what this layer leaves behind, as bullets under the ceiling's
// "This keeps:" list. The ceiling asks rather than saying it itself: what is on the
// box is this layer's business, and a ceiling that recited a fixed list told a
// balancer it was keeping a container runtime it never installed.
//
// The substrate stays because the apps that keep running may need it — removing
// another tool's packages is not the gate's call
// (decisions/uninstall-removes-the-gate.md). Only what is actually on the box is
// named, so the line is a report and not a claim.
//
// The restic repo gets the last word the box will have on it: the repo and its
// snapshots outlive the box, and without the password every backup is unreadable
// ciphertext. It prints *where* the password is, never the password. Uninstall keeps
// /var/lib/steward, so the file is still on the box for the operator who needs it —
// printing the secret itself bought nothing and spent it into terminal scrollback,
// the systemd journal, and the log of any automation that ran `uninstall --yes`. One
// more command for the person who needs it; nobody else ends up holding it.
func (Layer) TeardownNote(w io.Writer) {
	var kept []string
	for _, t := range tools(core.Role()) {
		if core.Have(t.name) {
			kept = append(kept, t.name)
		}
	}
	if len(kept) > 0 {
		fmt.Fprintf(w, "  - %s — steward installed them; it does not remove them\n",
			strings.Join(kept, ", "))
	}

	cfg, ok := loadBackupConfig()
	if !ok {
		return
	}
	fmt.Fprintf(w, "  - the restic repo %s — it outlives this box\n", cfg.Repo)
	if _, err := os.Stat(resticPasswordFile()); err != nil {
		fmt.Fprintln(w, "    No password file on this box — if the repo matters, find its password")
		fmt.Fprintln(w, "    before wiping anything, or the snapshots are unreadable ciphertext.")
		return
	}
	fmt.Fprintln(w, "    Without the password every backup is unreadable. Copy it somewhere safe now:")
	fmt.Fprintf(w, "      sudo cat %s\n", resticPasswordFile())
	fmt.Fprintf(w, "    It stays readable on this box until you wipe %s.\n", secretsDir())
}
