package core

import (
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func useTempKeys(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "authorized_keys")
	t.Setenv(AuthorizedKeysEnv, path)
	return path
}

const testKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITESTKEY ci@laptop"

func TestAuthorizeWritesForcedLine(t *testing.T) {
	path := useTempKeys(t)

	if res := authorizeCmd([]string{testKey, "--client", "ci", "--scope", "operate"}); res.Code != "ok" {
		t.Fatalf("authorize: %+v", res)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	line := string(data)
	for _, want := range []string{
		`command="`, "_exec --client ci --scope operate", "restrict", testKey,
	} {
		if !strings.Contains(line, want) {
			t.Errorf("authorized_keys missing %q\ngot: %s", want, line)
		}
	}
	if strings.Contains(line, "restrict,pty") {
		t.Error("operate grant should not allow a pty")
	}
}

// No scope gets a pty any more — the top rung used to, because it handed out an
// interactive shell as the steward user, and that capability is gone.
// See decisions/no-key-gets-a-shell.md.
func TestNoScopeGetsAPty(t *testing.T) {
	for _, sc := range []string{"observe", "operate", "grant"} {
		useTempKeys(t)
		if res := authorizeCmd([]string{testKey, "--client", "c", "--scope", sc}); res.Code != "ok" {
			t.Fatalf("authorize at %s: %+v", sc, res)
		}
		path, _ := AuthorizedKeysPath()
		data, _ := os.ReadFile(path)
		if strings.Contains(string(data), "pty") {
			t.Errorf("scope %q was granted a pty\ngot: %s", sc, data)
		}
	}
}

// The retired `ssh` name still authorizes, so the documented onboarding line and any
// runbook that predates the rename keep working — but it is written down as `grant`,
// so the ledger converges and nobody is left holding a scope that no longer exists.
func TestSshScopeIsAcceptedAndWrittenAsGrant(t *testing.T) {
	useTempKeys(t)
	res := authorizeCmd([]string{testKey, "--client", "human", "--scope", "ssh"})
	if res.Code != "ok" {
		t.Fatalf("authorize --scope ssh: %+v", res)
	}
	path, _ := AuthorizedKeysPath()
	data, _ := os.ReadFile(path)
	if !strings.Contains(string(data), "--scope grant") {
		t.Errorf("`ssh` should be written as `grant`\ngot: %s", data)
	}
	if strings.Contains(string(data), "--scope ssh") {
		t.Errorf("the retired name was written to the ledger\ngot: %s", data)
	}
}

// A key authorized before the rename carries `--scope ssh` in its forced command. It
// must still resolve — at grant rank, and still without a shell.
func TestRetiredSshGrantStillResolves(t *testing.T) {
	if got := normalizeScope(retiredScopeSSH); got != ScopeGrant {
		t.Errorf("normalizeScope(ssh) = %q, want %q", got, ScopeGrant)
	}
	if d := decideExec(normalizeScope(retiredScopeSSH), "authorize k --client x --scope observe"); !d.allow {
		t.Errorf("a pre-rename ssh key should still grant: %s", d.reason)
	}
	if d := decideExec(normalizeScope(retiredScopeSSH), ""); d.allow {
		t.Error("a pre-rename ssh key must no longer get a shell")
	}
}

func TestAuthorizeReplacesClientLine(t *testing.T) {
	path := useTempKeys(t)
	authorizeCmd([]string{testKey, "--client", "ci", "--scope", "operate"})
	authorizeCmd([]string{testKey, "--client", "ci", "--scope", "observe"}) // re-grant, lower scope

	data, _ := os.ReadFile(path)
	if n := strings.Count(string(data), clientMarker("ci")); n != 1 {
		t.Fatalf("expected one ci line after re-authorize, got %d", n)
	}
	if !strings.Contains(string(data), "--scope observe") {
		t.Error("re-authorize did not update the scope")
	}
}

func TestRevokeRemovesOnlyThatClient(t *testing.T) {
	path := useTempKeys(t)
	authorizeCmd([]string{testKey, "--client", "ci", "--scope", "operate"})
	authorizeCmd([]string{testKey, "--client", "console", "--scope", "operate"})

	if res := revokeCmd([]string{"ci"}); res.Code != "ok" {
		t.Fatalf("revoke ci: %+v", res)
	}
	data, _ := os.ReadFile(path)
	if strings.Contains(string(data), clientMarker("ci")) {
		t.Error("ci line still present after revoke")
	}
	if !strings.Contains(string(data), clientMarker("console")) {
		t.Error("revoke removed the wrong client")
	}
	if res := revokeCmd([]string{"ci"}); res.Code != "not_found" {
		t.Errorf("revoking a missing client: got %q, want not_found", res.Code)
	}
}

func TestAuthorizeRejectsBadInput(t *testing.T) {
	useTempKeys(t)
	cases := []struct {
		name string
		args []string
	}{
		{"no pubkey", []string{"--client", "ci", "--scope", "operate"}},
		{"no client", []string{testKey, "--scope", "operate"}},
		{"bad scope", []string{testKey, "--client", "ci", "--scope", "root"}},
		{"bad client", []string{testKey, "--client", "ci;rm", "--scope", "operate"}},
		{"not a key", []string{"hello there", "--client", "ci", "--scope", "operate"}},
	}
	for _, c := range cases {
		if res := authorizeCmd(c.args); res.Code != "bad_args" {
			t.Errorf("%s: got %q, want bad_args", c.name, res.Code)
		}
	}
}

func TestDecideExec(t *testing.T) {
	cases := []struct {
		name      string
		granted   Scope
		original  string
		wantAllow bool
		wantName  string
		wantJSON  bool
	}{
		{"operate can deploy", ScopeOperate, "deploy web --image x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", true, "deploy", false},
		{"observe cannot deploy", ScopeObserve, "deploy web", false, "deploy", false},
		{"observe can read", ScopeObserve, "status", true, "status", false},
		{"operate can read (ladder)", ScopeOperate, "logs web", true, "logs", false},
		{"grant outranks operate", ScopeGrant, "deploy web --image x@sha256:abc0000000000000000000000000000000000000000000000000000000000000", true, "deploy", false},
		{"operate cannot grant", ScopeOperate, "authorize key --client x", false, "authorize", false},
		{"grant can grant", ScopeGrant, "authorize key --client x --scope observe", true, "authorize", false},
		{"machine ceiling refused even at the top rung", ScopeGrant, "prepare", false, "prepare", false},
		{"system command refused", ScopeOperate, "snapshot", false, "snapshot", false},
		{"unknown refused", ScopeOperate, "destroy-everything", false, "destroy-everything", false},
		{"_exec recursion refused", ScopeGrant, "_exec --client x --scope grant", false, "_exec", false},
		{"json passthrough", ScopeOperate, "--json status", true, "status", true},
		{"json trailing (ssh-safe)", ScopeObserve, "status --json", true, "status", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			d := decideExec(c.granted, c.original)
			if d.allow != c.wantAllow {
				t.Fatalf("allow = %v, want %v (reason: %s)", d.allow, c.wantAllow, d.reason)
			}
			if d.name != c.wantName {
				t.Errorf("name = %q, want %q", d.name, c.wantName)
			}
			if d.jsonOut != c.wantJSON {
				t.Errorf("jsonOut = %v, want %v", d.jsonOut, c.wantJSON)
			}
		})
	}
}

// The property the rename exists for: there is no scope, and no input, that turns a
// key into a shell. An empty command is the old door — it used to mean "give me a
// terminal" at the top rung. Now it means nothing at every rung.
func TestNoScopeGetsAShell(t *testing.T) {
	for _, granted := range []Scope{ScopeObserve, ScopeOperate, ScopeGrant, retiredScopeSSH, "", "root", "system"} {
		for _, original := range []string{"", "   ", "\t\n", "-", "--"} {
			d := decideExec(normalizeScope(granted), original)
			if d.allow {
				t.Errorf("scope %q with command %q was allowed (name %q)", granted, original, d.name)
			}
		}
	}
	// And there is no code path left that could exec one.
	if strings.Contains(gateSource(t), "syscall.Exec") {
		t.Error("auth.go still contains a process-replacing exec")
	}
}

func gateSource(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile("auth.go")
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestAuthExecRecordsAndEnforces(t *testing.T) {
	useTempKeys(t)
	recPath := filepath.Join(t.TempDir(), "record.log")
	t.Setenv("STEWARD_RECORD", recPath)

	// An observe grant asking to deploy is denied — and the attempt is recorded.
	t.Setenv("SSH_ORIGINAL_COMMAND", "deploy web --image x@sha256:abc0000000000000000000000000000000000000000000000000000000000000")
	if code := authExec([]string{"--client", "ci", "--scope", "observe"}, nonRootUID); code != 1 {
		t.Fatalf("denied exec should exit 1, got %d", code)
	}
	last, found, err := lastEntry(recPath)
	if err != nil || !found {
		t.Fatalf("expected a denial record: found=%v err=%v", found, err)
	}
	if last.Actor != "ci" || last.Scope != "deny" || last.Action != "deny:deploy" {
		t.Errorf("denial entry = %+v", last)
	}
}

// With no override, the ledger path is the running (effective) user's own
// authorized_keys, resolved from the passwd db — so it is correct under
// `sudo -u steward`, where $HOME may still be root's.
func TestAuthorizedKeysPathResolvesEffectiveUserHome(t *testing.T) {
	t.Setenv(AuthorizedKeysEnv, "") // empty override = use the default resolution
	u, err := user.LookupId(strconv.Itoa(os.Geteuid()))
	if err != nil {
		t.Skipf("cannot resolve current user: %v", err)
	}
	got, err := AuthorizedKeysPath()
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(u.HomeDir, ".ssh", "authorized_keys"); got != want {
		t.Errorf("authorizedKeysPath = %q, want %q", got, want)
	}
}
