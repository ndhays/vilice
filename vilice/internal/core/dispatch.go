// Package core is the trust layer: the one door, the account gate, the
// hash-chained record, and the root ceiling. It dispatches to the app layer but
// never knows what a verb does — see decisions/roles-not-packs.md.
package core

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/user"
	"strconv"
	"strings"
)

// Scope places a command relative to the legible ceiling. root commands are the
// god-key floor — run by the operator on the box, never reachable through a
// scoped key. The rest map onto the SSH Scope ladder (grant ⊃ operate ⊃ observe).
type Scope string

const (
	ScopeRoot    Scope = "root"    // ceiling: provisioning + identity, not via scoped SSH
	ScopeOperate Scope = "operate" // deploy + lifecycle
	ScopeObserve Scope = "observe" // read the record
	ScopeSystem  Scope = "system"  // systemd-invoked, not a human verb
	ScopeGrant   Scope = "grant"   // top rung: mint and revoke keys — and nothing else

	// retiredScopeSSH is the old name for the top rung (normalizeScope maps it to
	// scopeGrant). It used to hand out an interactive shell, which is precisely the
	// capability that was removed: see decisions/no-key-gets-a-shell.md. It now
	// survives for *input* only — a runbook or script that still types `--scope ssh`.
	// It no longer rescues old keys: a line written before the renames names the
	// `hostler` or `steward` binary, which are gone, so it fails closed either way. See
	// decisions/the-name-is-vilice.md.
	retiredScopeSSH Scope = "ssh"
)

// Result is the structured outcome of a command. Writes return it as JSON under
// --json so callers get a stable {code, retryable} taxonomy instead of scraping
// text. code "ok" means success; anything else is a failure with that code.
type Result struct {
	Code      string `json:"code"`
	Retryable bool   `json:"retryable"`
	Message   string `json:"message,omitempty"`
	// Data carries structured output for reads (status, doctor). Writes leave it
	// nil. Human output renders Message; --json includes Data.
	Data any `json:"data,omitempty"`
}

func OK(msg string) Result { return Result{Code: "ok", Message: msg} }

func notImplemented(name string) Result {
	return Result{
		Code:      "not_implemented",
		Retryable: false,
		Message:   fmt.Sprintf("%q is scaffolded but not yet implemented", name),
	}
}

// Flag is one --flag a command accepts, and what it is for. The list is the only
// source: the gate refuses anything not named here (see unknownFlag), and help
// prints the same list — so a flag cannot reach the box without being documented.
type Flag struct {
	Name string // without the leading --
	// Alias is the short spelling, without the dash ("n" for --tail). The gate
	// rewrites it to Name before any command sees it, so a command only ever parses
	// one spelling — and help prints it, so a short form cannot exist undocumented
	// the way `-y` did while the page named only `--yes`.
	Alias string
	Arg   string // "" for a boolean flag; otherwise the value's placeholder
	What  string // one line: what it does, and its default if it has one
}

// Example is an invocation you can paste, and the one line that says why.
type Example struct {
	Cmd  string
	What string
}

type Command struct {
	Name    string
	Scope   Scope
	Summary string
	// Long is the paragraph under the summary: what the command does, and what it
	// does not. Hard-wrapped by the author at HelpWidth; printed verbatim.
	Long string
	// Usage is the synopsis after "vilice <name>"; "" means the command takes
	// nothing. It is the single source for `help <name>`, `--help`, and the line
	// appended to every bad_args error — one string, so help and errors can't drift.
	Usage string
	// Flags is every --flag the command accepts. Anything else is refused before
	// the command runs: ParseArgs drops unknown flags, and a typo silently
	// ignored (`--por 9000`) is how the wrong thing gets deployed.
	Flags []Flag
	// Examples are shown after the flags. Two or three at most — a page nobody
	// finishes reading documents nothing.
	Examples []Example
	Run      func(args []string) Result
	// SkipBinaryCheck exempts a verb from the running-binary integrity check, so
	// it still works on a box whose binary was replaced or never recorded. Only
	// the verbs an operator inspects and repairs with are exempt: the root
	// ceiling, the rights ledger, and the record's own reads. Everything else is
	// checked, and a new verb is checked by default — the field says when *not*
	// to, so forgetting it fails closed. See digest.go.
	SkipBinaryCheck bool
}

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

func stub(name string) func([]string) Result {
	return func([]string) Result { return notImplemented(name) }
}

func Lookup(name string) (Command, bool) {
	for _, c := range Commands {
		if c.Name == name {
			return c, true
		}
	}
	return Command{}, false
}

// needsViliceUser reports whether a command must run as the unprivileged vilice
// user rather than root. Only the machine ceiling (prepare/harden) and the
// systemd-invoked recorder (snapshot, scopeSystem) may run as root; everything else
// is the _vilice user's. (snapshot stays root until the rootless-Podman migration —
// see decisions/ceiling-is-the-machine.md.)
func needsViliceUser(s Scope) bool {
	return s != ScopeRoot && s != ScopeSystem
}

// Main is the process entry, called by cmd/vilice once the app layer is registered. It
// returns the exit code rather than calling os.Exit, so every path through the
// gate is reachable from a test.
func Main(args []string) int {
	if len(args) == 0 {
		usage(os.Stderr)
		return 2
	}

	switch args[0] {
	case "version", "--version", "-v":
		fmt.Printf("vilice v%s\n", Version)
		return 0
	case "help", "--help", "-h":
		if len(args) > 1 {
			cmd, found := Lookup(args[1])
			if !found {
				fmt.Fprintf(os.Stderr, "vilice: unknown command %q (try `vilice help`)\n", args[1])
				return 2
			}
			commandHelp(os.Stdout, cmd)
			return 0
		}
		usage(os.Stdout)
		return 0
	case "_exec":
		// Internal: sshd invokes this via the forced command. Not a user verb.
		return authExec(args[1:], os.Geteuid())
	case "_man":
		// Internal: emit the man page (roff), generated from the commands table.
		// `make man` captures it as vilice.1.
		writeMan(os.Stdout)
		return 0
	case "_commands":
		// Internal: emit the commands table as JSON, each entry carrying the very
		// page `--help` prints. The documentation site builds itself from this.
		if err := writeCommandsJSON(os.Stdout); err != nil {
			fmt.Fprintf(os.Stderr, "vilice: %v\n", err)
			return 1
		}
		return 0
	}

	jsonOut, name, rest, ok := parseInvocation(args)
	if !ok {
		usage(os.Stderr)
		return 2
	}
	cmd, found := Lookup(name)
	if !found {
		fmt.Fprintf(os.Stderr, "vilice: unknown command %q (try `vilice help`)\n", name)
		return 2
	}
	return enter(cmd, rest, ActorName(), jsonOut, os.Geteuid())
}

// enter is the one door into every command: the account gate, then dispatch. Both
// entry points come through it — the local CLI above and the sshd forced command
// (`_exec`, in auth.go) — so there is no way in that skips the gate. That single
// door is what makes un-bypassability checkable; when `_exec` had its own path, the
// gate simply wasn't on it. euid is a parameter so the gate is testable off-box.
func enter(cmd Command, args []string, actorName string, jsonOut bool, euid int) int {
	refusal := fmt.Sprintf("%s runs as the _vilice user — try: sudo -u _vilice vilice %s",
		cmd.Name, cmd.Name)
	if !userGate(cmd.Scope, euid, jsonOut, refusal) {
		return 1
	}
	return Dispatch(cmd, args, actorName, jsonOut)
}

// userGate enforces one vilice per box: non-ceiling commands run as exactly the
// _vilice user. Run as anyone else — root included — Podman/Quadlet state lands in
// *that* user's home: a healthy-looking ghost install the _vilice user has never heard
// of. Where no _vilice account exists (dev boxes, CI), refuse only bare root, as
// before. Returns false having already emitted refusal as the message — the caller
// supplies it, because "run it as _vilice instead" is the right advice for a command
// and the wrong advice for a shell grant pinned into the wrong account.
// See decisions/one-vilice-per-box.md.
func userGate(s Scope, euid int, jsonOut bool, refusal string) bool {
	uid, exists := viliceUID()
	if !wrongUser(s, euid, uid, exists) {
		return true
	}
	emit(Result{Code: "wrong_user", Message: refusal}, jsonOut)
	return false
}

// wrongUser decides whether an invocation is refused for running as the wrong
// account. Pure, so the gate is testable: euid is the caller, viliceUID the box's
// _vilice account (found=false where none exists).
func wrongUser(s Scope, euid, viliceUID int, found bool) bool {
	if !needsViliceUser(s) {
		return false
	}
	if found {
		return euid != viliceUID
	}
	return euid == 0
}

// viliceUID resolves the _vilice account, if this box has one (prepare creates it).
func viliceUID() (int, bool) {
	u, err := user.Lookup(ViliceUser)
	if err != nil {
		return 0, false
	}
	uid, err := strconv.Atoi(u.Uid)
	return uid, err == nil
}

// parseInvocation pulls out the --json flag (in any position) and returns the
// command name and remaining args. Position-independent on purpose: an ssh client
// rejects a remote command that starts with "--", so callers send `status --json`,
// not `--json status`. Shared by the local path and the scoped-SSH path (_exec).
func parseInvocation(args []string) (jsonOut bool, name string, rest []string, ok bool) {
	var filtered []string
	for _, a := range args {
		if a == "--json" {
			jsonOut = true
			continue
		}
		filtered = append(filtered, a)
	}
	if len(filtered) == 0 {
		return jsonOut, "", nil, false
	}
	return jsonOut, filtered[0], filtered[1:], true
}

// Dispatch records a state-changing command (invariant 2), then runs it.
// actorName is the named actor written to the record. Returns the exit code.
func Dispatch(cmd Command, args []string, actorName string, jsonOut bool) int {
	// `--help` anywhere is a request for the page, never a run — it must not fall
	// through to the action it was asking about (`remove <app> --help` removes
	// nothing). A read, so it is not recorded — same as an unknown command.
	if hasFlag(args, "--help", "-h") {
		commandHelp(os.Stdout, cmd)
		return 0
	}
	// One spelling past this point. Short forms are rewritten to their long names
	// here, at the gate, so no command has to know a short form exists — a command
	// that parsed its own aliases is how `logs` ended up with a second flag parser
	// and a silently-dropped `--tail=100`.
	args = normalizeAliases(cmd, args)
	// A boolean flag is present or absent; giving it a value is refused rather than
	// interpreted. `--yes=false` plainly reads as "no", and every way of honouring it
	// is wrong: treat presence as true and it means yes, parse the value and `--yes`
	// alone becomes the odd one out. Refusing says so in one line.
	if bad := booleanWithValue(cmd, args); bad != "" {
		emit(withUsage(cmd, Result{Code: "bad_args",
			Message: fmt.Sprintf("%s takes no value", bad)}), jsonOut)
		return 1
	}
	// A flag the command doesn't declare is a hard error (fail loud): parseArgs
	// would silently drop it, and a typo like `--por 9000` deploying on the default
	// port is exactly the quiet failure the record exists to prevent. Refused
	// before recording, like an unknown command.
	if bad := unknownFlag(cmd, args); bad != "" {
		emit(withUsage(cmd, Result{Code: "bad_args",
			Message: fmt.Sprintf("unknown flag %s", bad)}), jsonOut)
		return 1
	}
	// An app name becomes a filesystem path (its state file, its Quadlet unit) and a
	// systemd unit name, so `remove ../../x` must never get as far as the command.
	// Checked here, once, for every command that takes one — deploy validated its own
	// and the five lifecycle verbs did not, which is how the gap opened.
	if bad := badAppArg(cmd, args); bad != "" {
		emit(withUsage(cmd, Result{Code: "bad_args", Message: fmt.Sprintf(
			"app name %q must be [A-Za-z0-9_-]", bad)}), jsonOut)
		return 1
	}
	// A verb acts only if the running binary is the one this box recorded. The few
	// verbs an operator inspects and repairs with are exempt — which is what keeps
	// `verify`, `record`, and `authorize` working on a box whose digest record is
	// missing or stale, so the operator can see why and fix it. See digest.go.
	//
	// The refusal is recorded, best-effort: "the installed binary is not the one
	// this box authorized" is exactly the event the record exists for, and unlike a
	// typo'd flag it is not the caller's mistake. A failure to write it must not
	// turn a refusal into a run, so the error is dropped, as with a denied key in
	// auth.go.
	digest := ""
	if !cmd.SkipBinaryCheck {
		d, err := checkBinaryDigest()
		if err != nil {
			_ = Record(actorName, "deny", "binary-unrecognized", []string{cmd.Name})
			emit(Result{Code: "binary_unrecognized", Message: err.Error()}, jsonOut)
			return 1
		}
		digest = d
	}
	// Make the resolved actor available to the command itself (deploy records its
	// own spec entry). actor() reads VILICE_ACTOR.
	_ = os.Setenv("VILICE_ACTOR", actorName) // only errors on a NUL byte in name/value
	if recordable(cmd, args) {
		// If the record can't be written, we don't act — fail loud, retryable.
		if err := RecordAct(actorName, string(cmd.Scope), cmd.Name, args, digest); err != nil {
			emit(Result{Code: "record_failed", Retryable: true, Message: err.Error()}, jsonOut)
			return 1
		}
	}
	res := runQuietly(cmd, args, jsonOut)
	emit(withUsage(cmd, res), jsonOut)
	if res.Code != "ok" {
		return 1
	}
	return 0
}

// runQuietly runs the command and, under --json, keeps stdout for the reply alone.
//
// A verb drives other tools — apt, podman, caddy, systemctl — and hands them this
// process's stdout so a person at a shell sees them work. A machine reading --json
// wants one JSON document on stdout and nothing else, and it was getting apt's whole
// transcript in front of it: `apply-updates` succeeded on the box and failed to parse in
// the console, every time. So for the length of the run, stdout *is* stderr: the tools'
// output still arrives, on the stream meant for it, and the reply is the only thing on
// stdout. The contract a caller can rely on is "stdout is the Result; stderr is the log".
func runQuietly(cmd Command, args []string, jsonOut bool) Result {
	if !jsonOut {
		return cmd.Run(args)
	}
	reply := os.Stdout
	os.Stdout = os.Stderr
	defer func() { os.Stdout = reply }()
	return cmd.Run(args)
}

// normalizeAliases rewrites a command's declared short flags to their long names,
// carrying any `=value` across. Only exact matches are touched, so an app named `-n`
// — which the name rules permit — is not quietly turned into a flag.
func normalizeAliases(cmd Command, args []string) []string {
	out := make([]string, len(args))
	copy(out, args)
	for _, f := range cmd.Flags {
		if f.Alias == "" {
			continue
		}
		short, long := "-"+f.Alias, "--"+f.Name
		for i, a := range out {
			switch {
			case a == short:
				out[i] = long
			case strings.HasPrefix(a, short+"="):
				out[i] = long + strings.TrimPrefix(a, short)
			}
		}
	}
	return out
}

// booleanWithValue returns the first boolean flag given a value ("" if none).
//
// `--json` is included though no command declares it: it is the global read flag,
// stripped by parseInvocation in its bare form only, so `--json=true` would otherwise
// reach unknownFlag and be reported as "unknown flag --json" — which is both wrong
// and confusing, since --json is the one flag every command takes.
func booleanWithValue(cmd Command, args []string) string {
	for _, a := range args {
		if !strings.HasPrefix(a, "--") {
			continue
		}
		name, _, valued := strings.Cut(strings.TrimPrefix(a, "--"), "=")
		if !valued {
			continue
		}
		if name == "json" {
			return "--json"
		}
		for _, f := range cmd.Flags {
			if f.Name == name && f.Arg == "" {
				return "--" + f.Name
			}
		}
	}
	return ""
}

// unknownFlag returns the first --flag the command does not declare ("" if none).
// Long flags only: parseArgs treats every --token as a flag, so an undeclared one
// would otherwise vanish without a trace. --json is global and already stripped.
func unknownFlag(cmd Command, args []string) string {
	for _, a := range args {
		if !strings.HasPrefix(a, "--") {
			continue
		}
		name := strings.TrimPrefix(a, "--")
		if i := strings.IndexByte(name, '='); i >= 0 {
			name = name[:i]
		}
		if !declares(cmd, name) {
			return "--" + name
		}
	}
	return ""
}

// declares reports whether the command names this flag. The same list is what
// help prints, so the set the gate admits and the set the docs show are one set.
func declares(cmd Command, name string) bool {
	for _, f := range cmd.Flags {
		if f.Name == name {
			return true
		}
	}
	return false
}

// takesAppArg reports whether a command's first positional is an app name, read off
// the synopsis that already drives help and usage errors. Deriving it from the one
// string keeps a new command from quietly opting out of validation: write `<app>` in
// the synopsis and the check comes with it.
func takesAppArg(cmd Command) bool { return strings.Contains(cmd.Usage, "<app>") }

// badAppArg returns the first positional of an app-taking command when it isn't a
// valid app name ("" when fine). An absent positional is the command's own error to
// report ("missing <app>"), not this gate's.
func badAppArg(cmd Command, args []string) string {
	if !takesAppArg(cmd) {
		return ""
	}
	_, pos := ParseArgs(args)
	if len(pos) == 0 || ValidAppName(pos[0]) {
		return ""
	}
	return pos[0]
}

// withUsage appends the synopsis to a bad_args failure, so the error and the help
// are the same string and cannot drift.
func withUsage(cmd Command, res Result) Result {
	if res.Code != "bad_args" {
		return res
	}
	res.Message = strings.TrimRight(res.Message, "\n") + "\nusage: vilice " + synopsis(cmd)
	return res
}

func synopsis(cmd Command) string {
	if cmd.Usage == "" {
		return cmd.Name
	}
	return cmd.Name + " " + cmd.Usage
}

// Actor is the named Actor for a local invocation. Until auth supplies it (the
// authenticated key's client name, over _exec), it defaults to the human at the
// shell.
func ActorName() string {
	if a := os.Getenv("VILICE_ACTOR"); a != "" {
		return a
	}
	return "operator"
}

// recordable reports whether an invocation writes to the accountability record before
// it runs (invariant 2). Scoped writes do; reads do not. `harden --check` is a read —
// it asserts posture, changes nothing, and must work before `prepare` lays the floor —
// so it is exempt, the same way `verify` is a read that isn't recorded.
func recordable(cmd Command, args []string) bool {
	switch cmd.Scope {
	case ScopeRoot, ScopeOperate, ScopeGrant:
		if cmd.Name == "harden" && hasFlag(args, "--check") {
			return false
		}
		return true
	default:
		return false
	}
}

func emit(res Result, jsonOut bool) {
	if jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(res)
		return
	}
	if res.Message != "" {
		fmt.Println(res.Message)
	} else {
		fmt.Println(res.Code)
	}
}

// HelpWidth is the column every help page is written to fit. Eighty is the
// terminal nobody has to widen, and it is also what makes the page publishable:
// the docs site prints this text verbatim, and a line that wraps on a phone is a
// line that reads as broken. Authors hard-wrap Long to it; nothing here reflows.
const HelpWidth = 78

// commandHelp is the per-command page: what it does, how to call it, who may, and
// whether it is written down. Reached by `vilice help <name>`, by `--help`/`-h`
// on any command, and — verbatim — by the documentation site, which renders this
// output rather than describing it a second time. See
// decisions/help-is-the-documentation.md.
func commandHelp(w io.Writer, cmd Command) {
	fmt.Fprintf(w, "vilice %s — %s\n", cmd.Name, cmd.Summary)
	if cmd.Long != "" {
		fmt.Fprintf(w, "\n%s\n", strings.TrimRight(cmd.Long, "\n"))
	}

	fmt.Fprintln(w, "\nUsage:")
	fmt.Fprintf(w, "  vilice %s\n", synopsis(cmd))

	if len(cmd.Flags) > 0 {
		fmt.Fprintln(w, "\nFlags:")
		width := flagColumn(cmd.Flags)
		indent := strings.Repeat(" ", 2+width+2)
		for _, f := range cmd.Flags {
			lines := wrap(f.What, HelpWidth-len(indent))
			fmt.Fprintf(w, "  %-*s  %s\n", width, flagSpec(f), lines[0])
			for _, line := range lines[1:] {
				fmt.Fprintf(w, "%s%s\n", indent, line)
			}
		}
	}

	// What the example is for goes above the line you would type, not beside it: a
	// command long enough to need a continuation would otherwise sit level with its
	// own description, and you could not tell which was which.
	if len(cmd.Examples) > 0 {
		fmt.Fprintln(w, "\nExamples:")
		for i, ex := range cmd.Examples {
			if i > 0 {
				fmt.Fprintln(w)
			}
			for _, line := range wrap(ex.What, HelpWidth-2) {
				fmt.Fprintf(w, "  %s\n", line)
			}
			for _, line := range strings.Split(ex.Cmd, "\n") {
				fmt.Fprintf(w, "    %s\n", line)
			}
		}
	}

	fmt.Fprintf(w, "\nScope:  %s\n", scopeLine(cmd.Scope))
	fmt.Fprintf(w, "Record: %s\n", recordLine(cmd))
}

// wrap breaks a one-line description into lines of at most width columns, so
// authors write plain sentences and the renderer owns the shape. Always returns at
// least one line. Counts runes, not bytes — the help text is full of — and ….
func wrap(s string, width int) []string {
	var lines []string
	line := ""
	for _, word := range strings.Fields(s) {
		switch {
		case line == "":
			line = word
		case len([]rune(line))+1+len([]rune(word)) <= width:
			line += " " + word
		default:
			lines = append(lines, line)
			line = word
		}
	}
	return append(lines, line)
}

// flagSpec is how a flag is typed: --name, or --name <arg>, with the short form
// ahead of it when there is one. The short form is printed rather than mentioned in
// prose, so it is documented by the same list the gate admits.
func flagSpec(f Flag) string {
	s := "--" + f.Name
	if f.Alias != "" {
		s = "-" + f.Alias + ", " + s
	}
	if f.Arg == "" {
		return s
	}
	return s + " " + f.Arg
}

// flagColumn is the width the descriptions line up at — the longest spec, unless
// that would push the text past HelpWidth, in which case the ragged line is the
// lesser evil.
func flagColumn(flags []Flag) int {
	width := 0
	for _, f := range flags {
		if n := len(flagSpec(f)); n > width {
			width = n
		}
	}
	if max := HelpWidth / 2; width > max {
		return max
	}
	return width
}

// recordLine says whether an invocation lands in the accountable record before it
// runs. Help is the natural place to answer it: invariant 2 is the whole claim, and
// a reader should not have to infer which side of it a command is on.
func recordLine(cmd Command) string {
	switch {
	case recordable(cmd, nil):
		return "written before the command runs"
	case cmd.Scope == ScopeSystem:
		// snapshot is not recorded *by* the dispatcher because it is the thing
		// doing the recording. Saying "not recorded" here would be true of the
		// mechanism and false to the reader.
		return "this command is the record's heartbeat — it writes the entry"
	}
	return "not recorded — this command reads, it does not act"
}

// scopeLine says, in one line, who may run a command — help doubling as a second
// view of the rights ladder.
func scopeLine(s Scope) string {
	switch s {
	case ScopeRoot:
		return "root — run on the box as root; never reachable over scoped SSH"
	case ScopeGrant:
		return "grant — the top rung; mints and revokes keys. No scope grants a shell"
	case ScopeOperate:
		return "operate — reachable by an operate or grant key"
	case ScopeObserve:
		return "observe — reachable by any scoped key"
	case ScopeSystem:
		return "system — systemd-invoked; not a human verb"
	}
	return string(s)
}

func usage(w io.Writer) {
	fmt.Fprintf(w, "vilice v%s — one door to this box: named, scoped, recorded\n\n", Version)
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintln(w, "  vilice [--json] <command> [args]")
	fmt.Fprintln(w, "  vilice help [command] | version")
	fmt.Fprintln(w)
	section := ""
	for _, g := range Groups {
		// The section heads its run of groups, once. Upper-cased here rather than
		// stored that way, so the string stays a sentence for the renderers that
		// want it as one — the docs site sets its own case in CSS.
		if g.Section != section {
			section = g.Section
			fmt.Fprintf(w, "%s\n\n", strings.ToUpper(section))
		}
		printGroup(w, g.Title, g.Scope)
	}
	fmt.Fprintln(w, "Run `vilice help <command>` for the full page: what it does, every")
	fmt.Fprintln(w, "flag, examples, who may run it, and whether it is recorded.")
}

// Groups are the scopes as a reader meets them: the ceiling first, then the ladder
// from the top rung down, then the verb systemd calls. One order, used by `help`,
// by the man page, and by the documentation site's command index.
//
// Section is the coarser question a reader actually arrives with — *who runs this* —
// and it is the account, not the scope: the ceiling is the operator as root, the
// ladder is all the _vilice user, and snapshot is systemd. Consecutive groups share
// a section, and every renderer prints the section once, when it changes.
var Groups = []struct {
	Section string
	Title   string
	Scope   Scope
}{
	{"Run as root", "Box commands (root)", ScopeRoot},
	{"Run as _vilice", "Authorize", ScopeGrant},
	{"Run as _vilice", "Operate", ScopeOperate},
	{"Run as _vilice", "Observe", ScopeObserve},
	{"System-only", "Record", ScopeSystem},
}

func printGroup(w io.Writer, title string, s Scope) {
	fmt.Fprintf(w, "  %s:\n", title)
	for _, c := range Commands {
		if c.Scope == s {
			fmt.Fprintf(w, "    %-16s %s\n", c.Name, c.Summary)
		}
	}
	fmt.Fprintln(w)
}
