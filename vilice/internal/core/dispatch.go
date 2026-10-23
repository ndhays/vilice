// Package core is the trust layer: the one door, the account gate, the
// hash-chained record, and the root ceiling. It dispatches to the app layer but
// never knows what a verb does — see decisions/roles-not-packs.md.
package core

import (
	"encoding/json"
	"fmt"
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
	// RecordNote replaces the help page's "Record:" line for a command the dispatcher
	// does not record because it is not a person's act — the timer's snapshot, the
	// background half of an update. Saying "not recorded" would be true of the
	// mechanism and misleading about the record.
	RecordNote string
	// SkipBinaryCheck exempts a verb from the running-binary integrity check, so
	// it still works on a box whose binary was replaced or never recorded. Only
	// the verbs an operator inspects and repairs with are exempt: the root
	// ceiling, the rights ledger, and the record's own reads. Everything else is
	// checked, and a new verb is checked by default — the field says when *not*
	// to, so forgetting it fails closed. See digest.go.
	SkipBinaryCheck bool
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

// RunsAsVilice reports whether this process is the account an app-layer verb must run
// as — the same rule the gate applies to operate scope. A system-scoped verb is not
// gated (snapshot runs as root, from its timer), so one that touches Podman state has
// to ask for itself: run as anyone else, the state lands in that user's home.
func RunsAsVilice() bool {
	uid, found := viliceUID()
	return !wrongUser(ScopeOperate, os.Geteuid(), uid, found)
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
