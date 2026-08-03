package core

// Auth (invariant 1): every caller is a named actor with a declared scope, carried
// by scoped SSH. `authorize`/`revoke` manage forced-command lines in authorized_keys;
// `_exec` is the gate sshd runs — it turns "which key authenticated, asking for what"
// into a scope-checked, recorded command. See blueprint/steward/auth.md.

import (
	"errors"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
)

const AuthorizedKeysEnv = "STEWARD_AUTHORIZED_KEYS"

// AuthorizedKeysPath is the managed rights ledger. STEWARD_AUTHORIZED_KEYS
// overrides it (tests, non-default users).
func AuthorizedKeysPath() (string, error) {
	if p := os.Getenv(AuthorizedKeysEnv); p != "" {
		return p, nil
	}
	// Resolve the *effective* user's home from the passwd database, not $HOME: under
	// `sudo -u steward` $HOME may still be root's, but the ledger we manage is always
	// the running user's own authorized_keys. Run as steward, this is /home/steward.
	u, err := user.LookupId(strconv.Itoa(os.Geteuid()))
	if err != nil {
		return "", err
	}
	return filepath.Join(u.HomeDir, ".ssh", "authorized_keys"), nil
}

// --- authorize / revoke (root-only ceiling commands) ---

func authorizeCmd(args []string) Result {
	flags, positionals := ParseArgs(args)
	pubkey := strings.TrimSpace(strings.Join(positionals, " "))
	client := flags["client"]
	// `ssh` is accepted and written as `grant`, so the old onboarding line keeps working.
	sc := normalizeScope(Scope(flags["scope"]))

	switch {
	case pubkey == "":
		return Result{Code: "bad_args", Message: "missing <pubkey>"}
	case client == "":
		return Result{Code: "bad_args", Message: "missing --client"}
	case !validClient(client):
		return Result{Code: "bad_args", Message: "client must be [A-Za-z0-9_-]"}
	case !grantableScope(sc):
		return Result{Code: "bad_args", Message: "missing or invalid --scope (observe|operate|grant)"}
	case !looksLikePubkey(pubkey):
		return Result{Code: "bad_args", Message: "argument does not look like an SSH public key"}
	}

	path, err := AuthorizedKeysPath()
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	line, err := forcedLine(client, sc, pubkey)
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}

	// Re-authorizing a client replaces its line — idempotent, and lets the scope
	// change without leaving a stale grant behind.
	if _, err := removeClient(path, client); err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	if err := appendLine(path, line); err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	return OK(fmt.Sprintf("authorized %q at scope %q", client, sc))
}

func revokeCmd(args []string) Result {
	_, positionals := ParseArgs(args)
	client := strings.TrimSpace(strings.Join(positionals, " "))
	if client == "" {
		return Result{Code: "bad_args", Message: "missing <client>"}
	}
	path, err := AuthorizedKeysPath()
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	n, err := removeClient(path, client)
	if err != nil {
		return Result{Code: "io_error", Message: err.Error()}
	}
	if n == 0 {
		return Result{Code: "not_found", Message: fmt.Sprintf("no entry for %q", client)}
	}
	return OK(fmt.Sprintf("revoked %q (%d line(s))", client, n))
}

// forcedLine builds the pinned authorized_keys entry. The client name and granted
// scope live in the trusted forced command; `restrict` denies pty/agent/port/X11
// forwarding, at every scope without exception.
func forcedLine(client string, sc Scope, pubkey string) (string, error) {
	// The render boundary. authorizeCmd validates first, but this is the function that
	// turns a string into a line of the rights ledger, so it refuses here too: a
	// multi-line key writes a second grant carrying no forced command at all.
	if !validClient(client) || !grantableScope(sc) || !looksLikePubkey(pubkey) {
		return "", fmt.Errorf("refusing to write a ledger line from unvalidated input")
	}
	self, err := os.Executable()
	if err != nil {
		return "", err
	}
	// `restrict` for every scope, with no exception. It was `restrict,pty` at the top
	// rung, because that rung handed out an interactive shell; nothing does now, so no
	// key needs a terminal. See decisions/no-key-gets-a-shell.md.
	command := fmt.Sprintf("%s _exec --client %s --scope %s", self, client, sc)
	return fmt.Sprintf("command=%q,restrict %s", command, pubkey), nil
}

// clientMarker is the substring that identifies a client's line. The trailing
// space pins the whole token, so "ci" never matches "ci2".
func clientMarker(client string) string { return "--client " + client + " " }

// removeClient drops every line granting the named client. Returns how many.
func removeClient(path, client string) (int, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	marker := clientMarker(client)
	var kept []string
	removed := 0
	for _, ln := range NonEmptyLines(string(data)) {
		if strings.Contains(ln, marker) {
			removed++
			continue
		}
		kept = append(kept, ln)
	}
	if removed == 0 {
		return 0, nil
	}
	out := ""
	if len(kept) > 0 {
		out = strings.Join(kept, "\n") + "\n"
	}
	if err := os.WriteFile(path, []byte(out), 0o600); err != nil {
		return 0, err
	}
	return removed, nil
}

func appendLine(path, line string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(line + "\n")
	return err
}

// --- _exec: the boundary sshd runs ---

// authDecision is the outcome of resolving a scoped-SSH request. Pure to compute,
// so the gate's logic is testable without sshd.
type authDecision struct {
	allow   bool
	name    string // resolved command (if any)
	args    []string
	jsonOut bool
	reason  string // why denied
}

// decideExec is the whole gate, as a pure function: given the granted scope and the
// command the client asked sshd to run (SSH_ORIGINAL_COMMAND), decide what may run.
//
// Every grant resolves to a *named command* or to nothing. No scope turns an empty
// command into a shell — that is the whole point of the grant rung replacing the old
// `ssh` one. See decisions/no-key-gets-a-shell.md.
func decideExec(granted Scope, original string) authDecision {
	original = strings.TrimSpace(original)
	if original == "" {
		return authDecision{reason: "no command supplied — a key names what it wants to run; no scope grants a shell"}
	}

	jsonOut, name, rest, ok := parseInvocation(strings.Fields(original))
	if !ok {
		return authDecision{reason: "empty command"}
	}
	cmd, found := Lookup(name)
	if !found {
		return authDecision{reason: fmt.Sprintf("unknown command %q", name), name: name}
	}
	// The machine ceiling (prepare/harden) and the recorder (snapshot) are never
	// reachable over scoped SSH. Granting (authorize/revoke) is grant-scope — reachable
	// only by a grant-scope key, through the rank check below.
	if cmd.Scope == ScopeRoot || cmd.Scope == ScopeSystem {
		return authDecision{reason: fmt.Sprintf("%q is not permitted over scoped SSH", name), name: name}
	}
	if scopeRank(cmd.Scope) > scopeRank(granted) {
		return authDecision{reason: fmt.Sprintf("%q needs scope %q, grant is %q", name, cmd.Scope, granted), name: name}
	}
	return authDecision{allow: true, name: name, args: rest, jsonOut: jsonOut}
}

// authExec wraps decideExec with the trusted grant, recording, and execution. euid is
// the account sshd authenticated as; it goes through the same gate as the local CLI
// (main.go's enter) — the forced command is not a way around it.
func authExec(args []string, euid int) int {
	flags, _ := ParseArgs(args)
	client := flags["client"]
	granted := normalizeScope(Scope(flags["scope"]))
	if !validClient(client) || !grantableScope(granted) {
		emit(Result{Code: "bad_grant", Message: "forced command missing a valid --client/--scope"}, true)
		return 2
	}

	d := decideExec(granted, os.Getenv("SSH_ORIGINAL_COMMAND"))
	if !d.allow {
		// A refused attempt is accountable too — record who tried what.
		_ = Record(client, "deny", denyAction(d), nil)
		emit(Result{Code: "denied", Message: d.reason}, true)
		return 1
	}
	cmd, _ := Lookup(d.name) // decideExec already confirmed it exists
	return enter(cmd, d.args, client, d.jsonOut, euid)
}

// --- small helpers ---

func scopeRank(s Scope) int {
	switch s {
	case ScopeObserve:
		return 1
	case ScopeOperate:
		return 2
	case ScopeGrant:
		return 3
	default:
		return 0
	}
}

func grantableScope(s Scope) bool {
	return s == ScopeObserve || s == ScopeOperate || s == ScopeGrant
}

// normalizeScope maps the retired `ssh` name onto `grant`, so keys authorized before
// the rename keep working — they simply no longer get the shell that name promised,
// which is the point of the change. Accepted on input too, so the documented
// `--scope ssh` onboarding line doesn't break; `authorize` writes `grant` either way,
// and the ledger converges as clients are re-authorized.
// See decisions/no-key-gets-a-shell.md.
func normalizeScope(s Scope) Scope {
	if s == retiredScopeSSH {
		return ScopeGrant
	}
	return s
}

func validClient(c string) bool {
	if c == "" {
		return false
	}
	for _, r := range c {
		ok := r == '-' || r == '_' ||
			(r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !ok {
			return false
		}
	}
	return true
}

var pubkeyTypes = []string{"ssh-ed25519", "ssh-rsa", "ssh-dss", "ecdsa-sha2-", "sk-ssh-", "sk-ecdsa-"}

// looksLikePubkey checks that s is one authorized_keys key: a known type, a base64
// blob, and an optional comment — on a single line.
//
// The single line is the security part. forcedLine appends this text after the
// `command="…",restrict` options, so a newline in it writes a *second* line that
// carries no forced command and no restrictions at all — a full shell grant smuggled
// in as a key comment. The base64 check is what makes "one line" hold: it pins the
// key material to a charset with no whitespace in it.
func looksLikePubkey(s string) bool {
	if HasControlChar(s) {
		return false
	}
	fields := strings.Fields(s)
	if len(fields) < 2 {
		return false
	}
	known := false
	for _, t := range pubkeyTypes {
		if strings.HasPrefix(fields[0], t) {
			known = true
			break
		}
	}
	if !known || !isBase64(fields[1]) {
		return false
	}
	// type, blob, and at most a comment — anything more means extra options rode in.
	return len(fields) <= 3
}

func isBase64(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		ok := (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') ||
			(r >= '0' && r <= '9') || r == '+' || r == '/' || r == '='
		if !ok {
			return false
		}
	}
	return true
}

func denyAction(d authDecision) string {
	if d.name != "" {
		return "deny:" + d.name
	}
	return "deny"
}

// ParseArgs splits args into --flag values (--k v or --k=v) and bare positionals,
// in any order. Bare --flag (no value) maps to "". Enough for steward's commands.
func ParseArgs(args []string) (flags map[string]string, positionals []string) {
	flags = map[string]string{}
	for i := 0; i < len(args); i++ {
		a := args[i]
		if strings.HasPrefix(a, "--") {
			key := a[2:]
			if eq := strings.IndexByte(key, '='); eq >= 0 {
				flags[key[:eq]] = key[eq+1:]
				continue
			}
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "--") {
				flags[key] = args[i+1]
				i++
				continue
			}
			flags[key] = ""
			continue
		}
		positionals = append(positionals, a)
	}
	return flags, positionals
}

func NonEmptyLines(s string) []string {
	var out []string
	for _, ln := range strings.Split(s, "\n") {
		if strings.TrimSpace(ln) != "" {
			out = append(out, ln)
		}
	}
	return out
}
