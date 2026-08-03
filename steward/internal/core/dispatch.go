// Package core is the trust layer: the one door, the account gate, the
// hash-chained record, and the root ceiling. It dispatches to verb packs but
// never knows what a verb does — see decisions/core-and-packs.md.
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
	// It no longer rescues old keys: a line written before the steward rename names
	// the `hostler` binary, which is gone, so it fails closed either way. See
	// decisions/the-names-are-steward.md.
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

type Command struct {
	Name    string
	Scope   Scope
	Summary string
	// Usage is the synopsis after "steward <name>"; "" means the command takes
	// nothing. It is the single source for `help <name>`, `--help`, and the line
	// appended to every bad_args error — one string, so help and errors can't drift.
	Usage string
	// Flags is every --flag the command accepts. Anything else is refused before
	// the command runs: ParseArgs drops unknown flags, and a typo silently
	// ignored (`--por 9000`) is how the wrong thing gets deployed.
	Flags []string
	Run   func(args []string) Result
	// Pack is the pack that contributed this verb, set by Register. Empty means
	// the core's own — the verbs that constitute the trust model and can never be
	// a pack. A non-empty Pack is checked against the manifest before the verb
	// runs, and written to the record beside the action.
	Pack string
}

// Commands is every verb this binary can dispatch: the core's own, then those
// contributed by each registered pack, in registration order. Order within a scope
// is the order shown by `steward help`. Keep in sync with site/content/steward.md
// and blueprint/steward/.
//
// The core's verbs are the ones that constitute the trust model — the ceiling, the
// rights ledger, the record. They can never be a pack, or the trust model would
// have a plugin interface. See decisions/core-and-packs.md.
var Commands = []Command{
	// Ceiling — root only (machine mutation; not reachable via scoped SSH).
	{Name: "harden", Scope: ScopeRoot,
		Summary: "Optional OS / sshd hardening (first, before prepare)",
		Usage:   "[--check]", Flags: []string{"check"}, Run: hardenCmd},
	{Name: "prepare", Scope: ScopeRoot,
		Summary: "Install what the packs need and lay the accountability floor",
		Usage:   "[--yes]", Flags: []string{"yes"}, Run: prepareCmd},
	{Name: "uninstall", Scope: ScopeRoot,
		Summary: "Remove the gate and the scribe (apps keep running)",
		Usage:   "[--yes] [--remove-apps]", Flags: []string{"yes", "remove-apps"}, Run: uninstallCmd},

	// Access — grant scope (the top rung): manage the rights ledger, as the steward user.
	{Name: "authorize", Scope: ScopeGrant,
		Summary: "Admit a named actor at a scope (writes the authorized_keys line)",
		Usage:   "<pubkey> --client <name> --scope <observe|operate|grant>",
		Flags:   []string{"client", "scope"}, Run: authorizeCmd},
	{Name: "revoke", Scope: ScopeGrant,
		Summary: "Remove a named actor's authorized_keys line",
		Usage:   "<client>", Run: revokeCmd},

	// The machine itself — operate. (Whether this belongs in a steward-machine pack
	// is open: decisions/open/steward-open-questions.md.)
	{Name: "apply-updates", Scope: ScopeOperate,
		Summary: "Apply machine OS package updates", Run: applyUpdatesCmd},

	// The record — observe. Invariant 2's read side.
	{Name: "verify", Scope: ScopeObserve,
		Summary: "Check the record's hash chain is intact", Run: verifyCmd},
	{Name: "record", Scope: ScopeObserve,
		Summary: "Dump the accountable record (entries + chain check)", Run: recordCmd},

	// The rights ledger — observe. Invariant 1's read side: authorize writes it,
	// this reads it back, and no scoped key can do anything else with it.
	{Name: "actors", Scope: ScopeObserve,
		Summary: "List who may act on this box, at what scope", Run: actorsCmd},
	{Name: "packs", Scope: ScopeObserve,
		Summary: "List what code may run on this box, at what digest", Run: packsCmd},
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

// needsStewardUser reports whether a command must run as the unprivileged steward
// user rather than root. Only the machine ceiling (prepare/harden) and the
// systemd-invoked recorder (snapshot, scopeSystem) may run as root; everything else
// is the steward user's. (snapshot stays root until the rootless-Podman migration —
// see decisions/ceiling-is-the-machine.md.)
func needsStewardUser(s Scope) bool {
	return s != ScopeRoot && s != ScopeSystem
}

// Main is the process entry, called by cmd/steward once packs are registered. It
// returns the exit code rather than calling os.Exit, so every path through the
// gate is reachable from a test.
func Main(args []string) int {
	if len(args) == 0 {
		usage(os.Stderr)
		return 2
	}

	switch args[0] {
	case "version", "--version", "-v":
		fmt.Printf("steward v%s\n", Version)
		return 0
	case "help", "--help", "-h":
		if len(args) > 1 {
			cmd, found := Lookup(args[1])
			if !found {
				fmt.Fprintf(os.Stderr, "steward: unknown command %q (try `steward help`)\n", args[1])
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
		// `make man` captures it as steward.1.
		writeMan(os.Stdout)
		return 0
	}

	jsonOut, name, rest, ok := parseInvocation(args)
	if !ok {
		usage(os.Stderr)
		return 2
	}
	cmd, found := Lookup(name)
	if !found {
		fmt.Fprintf(os.Stderr, "steward: unknown command %q (try `steward help`)\n", name)
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
	refusal := fmt.Sprintf("%s runs as the steward user — try: sudo -u steward steward %s",
		cmd.Name, cmd.Name)
	if !userGate(cmd.Scope, euid, jsonOut, refusal) {
		return 1
	}
	return Dispatch(cmd, args, actorName, jsonOut)
}

// userGate enforces one steward per box: non-ceiling commands run as exactly the
// steward user. Run as anyone else — root included — Podman/Quadlet state lands in
// *that* user's home: a healthy-looking ghost install the steward user has never heard
// of. Where no steward account exists (dev boxes, CI), refuse only bare root, as
// before. Returns false having already emitted refusal as the message — the caller
// supplies it, because "run it as steward instead" is the right advice for a command
// and the wrong advice for a shell grant pinned into the wrong account.
// See decisions/one-steward-per-box.md.
func userGate(s Scope, euid int, jsonOut bool, refusal string) bool {
	uid, exists := stewardUID()
	if !wrongUser(s, euid, uid, exists) {
		return true
	}
	emit(Result{Code: "wrong_user", Message: refusal}, jsonOut)
	return false
}

// wrongUser decides whether an invocation is refused for running as the wrong
// account. Pure, so the gate is testable: euid is the caller, stewardUID the box's
// steward account (found=false where none exists).
func wrongUser(s Scope, euid, stewardUID int, found bool) bool {
	if !needsStewardUser(s) {
		return false
	}
	if found {
		return euid != stewardUID
	}
	return euid == 0
}

// stewardUID resolves the steward account, if this box has one (prepare creates it).
func stewardUID() (int, bool) {
	u, err := user.Lookup(StewardUser)
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
	// A packed verb runs only if the manifest says this pack may, at this binary's
	// digest. The core's own verbs carry no pack and skip this — which is what keeps
	// `verify`, `record`, and `authorize` working on a box whose manifest is missing
	// or stale, so the operator can see why and fix it.
	//
	// The refusal is recorded, best-effort: "the installed binary and the manifest
	// disagree" is exactly the event the record exists for, and unlike a typo'd flag
	// it is not the caller's mistake. A failure to write it must not turn a refusal
	// into a run, so the error is dropped, as with a denied key in auth.go.
	pack, digest := cmd.Pack, ""
	if pack != "" {
		if err := authorizePack(pack); err != nil {
			_ = Record(actorName, "deny", "pack-unauthorized", []string{pack, cmd.Name})
			emit(Result{Code: "pack_unauthorized", Message: err.Error()}, jsonOut)
			return 1
		}
		digest, _ = SelfDigest() // authorizePack just read it without error
	}
	// Make the resolved actor available to the command itself (deploy records its
	// own spec entry). actor() reads STEWARD_ACTOR.
	_ = os.Setenv("STEWARD_ACTOR", actorName) // only errors on a NUL byte in name/value
	if recordable(cmd, args) {
		// If the record can't be written, we don't act — fail loud, retryable.
		if err := RecordAct(actorName, string(cmd.Scope), cmd.Name, args, pack, digest); err != nil {
			emit(Result{Code: "record_failed", Retryable: true, Message: err.Error()}, jsonOut)
			return 1
		}
	}
	res := cmd.Run(args)
	emit(withUsage(cmd, res), jsonOut)
	if res.Code != "ok" {
		return 1
	}
	return 0
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
		if !containsString(cmd.Flags, name) {
			return "--" + name
		}
	}
	return ""
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

func containsString(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

// withUsage appends the synopsis to a bad_args failure, so the error and the help
// are the same string and cannot drift.
func withUsage(cmd Command, res Result) Result {
	if res.Code != "bad_args" {
		return res
	}
	res.Message = strings.TrimRight(res.Message, "\n") + "\nusage: steward " + synopsis(cmd)
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
	if a := os.Getenv("STEWARD_ACTOR"); a != "" {
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

// commandHelp is the per-command page: what it does, how to call it, who may.
// Reached by `steward help <name>` and by `--help`/`-h` on any command.
func commandHelp(w io.Writer, cmd Command) {
	fmt.Fprintf(w, "steward %s — %s\n\n", cmd.Name, cmd.Summary)
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintf(w, "  steward %s\n\n", synopsis(cmd))
	fmt.Fprintf(w, "Scope: %s\n", scopeLine(cmd.Scope))
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

func usage(w *os.File) {
	fmt.Fprintf(w, "steward v%s — one door to this box: named, scoped, recorded\n\n", Version)
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintln(w, "  steward [--json] <command> [args]")
	fmt.Fprintln(w, "  steward help [command] | version")
	fmt.Fprintln(w)
	printGroup(w, "Ceiling (root only — prepare and harden)", ScopeRoot)
	printGroup(w, "Access (grant scope — mint and revoke keys)", ScopeGrant)
	printGroup(w, "Deploy & lifecycle (operate)", ScopeOperate)
	printGroup(w, "Observe & record (observe)", ScopeObserve)
	printGroup(w, "Record (systemd-invoked)", ScopeSystem)
}

func printGroup(w *os.File, title string, s Scope) {
	fmt.Fprintf(w, "%s:\n", title)
	for _, c := range Commands {
		if c.Scope == s {
			fmt.Fprintf(w, "  %-14s %s\n", c.Name, c.Summary)
		}
	}
	fmt.Fprintln(w)
}
