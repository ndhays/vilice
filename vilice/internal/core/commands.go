package core

// Commands is every verb this binary can dispatch: the core's own, then those the
// app layer contributes. Order within a scope is the order shown by `vilice help`.
//
// This table is the only description of the CLI there is. `--help`, usage errors,
// vilice(1), and every page under /commands/ on the documentation site are views
// of it — the site prints commandHelp's output verbatim rather than describing a
// command a second time. So a verb is documented here or it is not documented:
// CheckDocs fails the build on a missing paragraph, an undescribed flag, or a line
// too wide for the block the site renders it in. See
// decisions/help-is-the-documentation.md and blueprint/vilice/overview.md.
//
// The core's verbs are the ones that constitute the trust model — the ceiling, the
// rights ledger, the record. See decisions/roles-not-packs.md.
var Commands = []Command{
	// Ceiling — root only (machine mutation; not reachable via scoped SSH). These
	// three skip the binary check: `harden` runs before the box has recorded a
	// digest, `prepare` is what records it, and `uninstall` has to be able to take
	// a tampered install off the box.
	{Name: "harden", Scope: ScopeRoot, SkipBinaryCheck: true,
		Summary: "Optional OS / sshd hardening (first, before prepare)",
		Long: `Locks down the operating system: key-only SSH, a firewall holding open
sshd's port alone, and fail2ban. These scripts know nothing about
Vilice — no _vilice user, no record, no containers — so a box is
hardened whether or not it ever runs an app.

Hardening is deliberately separate from prepare, and optional. The
accountability floor never lives here, so an un-hardened box is still
an accountable one. Run it first on a fresh machine, or skip it and
bring your own hardening.`,
		Usage: "[--check]",
		Flags: []Flag{
			{Name: "check", What: "Report drift instead of changing anything. A read: exits non-zero if the posture regressed, and is not recorded."},
		},
		Examples: []Example{
			{Cmd: "sudo vilice harden", What: "Lock the box down. Idempotent — re-running converges."},
			{Cmd: "sudo vilice harden --check", What: "Ask whether it is still locked down. Publishes the answer, so status and the console can show it."},
		},
		Run: hardenCmd},
	{Name: "prepare", Scope: ScopeRoot, SkipBinaryCheck: true,
		Summary: "Say what this box is for and lay the accountability floor",
		Long: `Declares the box's role, installs what that role needs, and lays the
accountability floor — the append-only record every later command
writes to. Required before any deploy.

  host      runs apps: Podman, restic and Caddy
  balancer  fronts other boxes: Caddy alone, and runs no apps

The role is written down, and re-preparing as a different role is
refused — converting a box is a decision, not a typo. Everything else
is idempotent: re-running after an upgrade converges whatever the new
version added, and is the normal thing to do, not a repair.

Opens the role's ports when a firewall is present, and shows an
apt-style summary for confirmation before it touches anything.`,
		Usage: "<host|balancer> [--yes]",
		Flags: []Flag{
			{Name: "yes", Alias: "y", What: "Skip the confirmation. For automation, not for haste."},
		},
		Examples: []Example{
			{Cmd: "sudo vilice prepare host", What: "Set this box up to run apps."},
			{Cmd: "sudo vilice prepare balancer --yes", What: "Set it up to front other boxes, unattended."},
		},
		Run: prepareCmd},
	{Name: "uninstall", Scope: ScopeRoot, SkipBinaryCheck: true,
		Summary: "Remove the gate and the scribe (apps keep running)",
		Long: `Removes Vilice: the snapshot timer, every scoped key, the sudoers
grant, the binary authorization, and the binary itself. What it does
not remove is anything that is running. Your apps are ordinary systemd
units behind ordinary Caddy config, and Vilice is not a runtime — so
uninstalling stops the gate and the record, and nothing else.

The _vilice user and /var/lib/vilice stay. The record is the box's
history and outlives the tool that wrote it.

If backups are configured it points at the restic repo and its
password file on the way out — the repo outlives the box, and without
the password every snapshot is unreadable ciphertext. It prints where
that password is, never the password itself.`,
		Usage: "[--yes] [--remove-apps]",
		Flags: []Flag{
			{Name: "yes", Alias: "y", What: "Skip the confirmation."},
			{Name: "remove-apps", What: "Take the apps down too. Without this they keep running."},
		},
		Examples: []Example{
			{Cmd: "sudo vilice uninstall", What: "Remove Vilice. The apps carry on serving."},
			{Cmd: "sudo vilice uninstall --remove-apps --yes", What: "Remove Vilice and everything it deployed."},
		},
		Run: uninstallCmd},

	// Access — grant scope (the top rung): manage the rights ledger, as the vilice
	// user. Both skip the binary check: withdrawing a key from a box you have
	// stopped trusting must not depend on the box being trustworthy.
	{Name: "authorize", Scope: ScopeGrant, SkipBinaryCheck: true,
		Summary: "Admit a named actor at a scope",
		Long: `Admits a named actor by writing one forced-command line into vilice's
authorized_keys. The key is the identity and the forced command is the
scope; there is no token to store and no shell to reach.

Scopes form a ladder — a higher one grants those below it:

  observe   read the record: status, logs, verify, record
  operate   deploy and lifecycle
  grant     mint and revoke keys, and nothing else

No scope is a shell. A key that sends no command is refused, which is
what makes the record complete: nothing acts on this box without an
entry being written first. If you want a real shell, use your own
account — that is a different named actor with its own trail.

authorized_keys is the rights ledger. Read it and you see every actor
and its ceiling. vilice actors reads it back.`,
		Usage: "<pubkey> --client <name> --scope <observe|operate|grant>",
		Flags: []Flag{
			{Name: "client", Arg: "<name>", What: "The actor's name. This is what lands in the record."},
			{Name: "scope", Arg: "<scope>", What: "observe, operate, or grant. (ssh is the retired name for the top rung and still reads as grant.)"},
		},
		Examples: []Example{
			{Cmd: `vilice authorize "$(cat console.pub)" --client console --scope operate`, What: "Admit the console so it can deploy."},
			{Cmd: `vilice authorize "$(cat ci.pub)" --client ci --scope observe`, What: "Let a CI job read the record and nothing more."},
		},
		Run: authorizeCmd},
	{Name: "revoke", Scope: ScopeGrant, SkipBinaryCheck: true,
		Summary: "Remove a named actor's authorized_keys line",
		Long: `Removes that actor's line from the rights ledger. The next connection
under that key is refused at sshd. Whatever the actor already did stays
in the record — revoking a key withdraws a capability, it does not
rewrite history.`,
		Usage: "<client>",
		Examples: []Example{
			{Cmd: "vilice revoke ci", What: "Withdraw the CI job's key."},
		},
		Run: revokeCmd},

	// The machine itself — operate.
	{Name: "apply-updates", Scope: ScopeOperate,
		Summary: "Apply machine OS package updates",
		Long: `Applies the operating system's pending package updates. This is the
_vilice user's one narrow root escalation, granted by a single line in
/etc/sudoers.d/vilice and nothing wider.

It patches the machine, not the apps. An app is whatever image its
spec pins, and is updated by deploying a new digest.`,
		Examples: []Example{
			{Cmd: "vilice apply-updates", What: "Patch the OS. Recorded, like every other act."},
		},
		Run: applyUpdatesCmd},

	// The record — observe. Invariant 2's read side. Both skip the binary check:
	// if a digest mismatch took these down with it, the operator would be locked
	// out of the very evidence that explains the refusal.
	{Name: "verify", Scope: ScopeObserve, SkipBinaryCheck: true,
		Summary: "Check the record's hash chain is intact",
		Long: `Walks the record from the beginning and confirms every entry still
hashes to the one after it. Exits non-zero and names the first break.

The record is a plain append-only file, one JSON object per line, and
each line carries the hash of the one before. Edit a line or delete
one and the chain stops matching from there on. That is the whole
mechanism — no database, no daemon, nothing to trust but arithmetic
you can redo yourself.`,
		Examples: []Example{
			{Cmd: "vilice verify", What: "Confirm nothing has been altered or removed."},
		},
		Run: verifyCmd},
	{Name: "record", Scope: ScopeObserve, SkipBinaryCheck: true,
		Summary: "Dump the accountable record (entries + chain check)",
		Long: `Prints the record: every entry, plus the chain-integrity check, so a
reader can show the witnessed history and prove it is unbroken.

The file itself is /var/lib/vilice/record.log — append-only, one JSON
object per line, readable with cat. This command is the convenient
door, not the only one.`,
		Examples: []Example{
			{Cmd: "vilice record", What: "Read the box's history."},
			{Cmd: "vilice record --json", What: "The same, structured, for a program to read."},
		},
		Run: recordCmd},

	// The rights ledger — observe. Invariant 1's read side: authorize writes it,
	// this reads it back, and no scoped key can do anything else with it.
	{Name: "actors", Scope: ScopeObserve, SkipBinaryCheck: true,
		Summary: "List who may act on this box, at what scope",
		Long: `Reads the rights ledger back: every named actor, its scope, and its
key fingerprint.

It also reports any line in authorized_keys that Vilice did not
write. A hand-added key reaches the box without passing the gate, so
it is exactly the thing worth surfacing rather than skipping over.`,
		Examples: []Example{
			{Cmd: "vilice actors", What: "See every key that can reach this box, and how far."},
		},
		Run: actorsCmd},
}
