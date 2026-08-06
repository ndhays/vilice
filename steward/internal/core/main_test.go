package core

import (
	"strings"
	"testing"
)

// nonRootUID stands in for an ordinary account in tests. On a box with no steward
// user (CI, dev), any non-root uid passes the account gate.
const nonRootUID = 1000

// One door: `enter` (the local CLI) and `authExec` (the sshd forced command) are the
// only ways to reach a command, and the account gate is on both. Root asking for a
// non-ceiling command is the same mistake either way — `sudo steward deploy` and
// `sudo steward _exec --scope operate` used to disagree, because the forced command
// had its own path around the gate.
//
// The assertion is the record, not the exit code: dispatch writes the entry *before*
// it acts, so an empty record proves the refusal happened ahead of any side effect.
// A bypass would leave a "deploy" entry behind.
func TestAccountGateIsOnEveryDoor(t *testing.T) {
	deploy, ok := Lookup("deploy")
	if !ok {
		t.Fatal("no deploy command")
	}

	t.Run("local CLI", func(t *testing.T) {
		path := useTempRecord(t)
		if code := enter(deploy, []string{"web"}, "operator", true, 0); code != 1 {
			t.Errorf("root ran a deploy: exit %d, want 1", code)
		}
		assertRecordEmpty(t, path)
	})

	t.Run("sshd forced command", func(t *testing.T) {
		path := useTempRecord(t)
		t.Setenv("SSH_ORIGINAL_COMMAND", "deploy web --image x@sha256:abc0000000000000000000000000000000000000000000000000000000000000")
		if code := authExec([]string{"--client", "ci", "--scope", "ssh"}, 0); code != 1 {
			t.Errorf("root ran a deploy through the forced command: exit %d, want 1", code)
		}
		assertRecordEmpty(t, path)
	})

	// An empty command used to be the shell door at the top rung. It is now refused at
	// every rung — and refused as a *denial*, which is itself recorded, so the attempt
	// is accountable rather than silent.
	t.Run("empty command at the top rung", func(t *testing.T) {
		path := useTempRecord(t)
		t.Setenv("SSH_ORIGINAL_COMMAND", "")
		if code := authExec([]string{"--client", "ci", "--scope", "grant"}, nonRootUID); code != 1 {
			t.Errorf("an empty command was allowed: exit %d, want 1", code)
		}
		entries, err := readEntries(path)
		if err != nil {
			t.Fatal(err)
		}
		if len(entries) != 1 || entries[0].Scope != "deny" {
			t.Errorf("the refused attempt should be recorded as a denial, got %+v", entries)
		}
	})
}

func assertRecordEmpty(t *testing.T, path string) {
	t.Helper()
	entries, err := readEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 0 {
		t.Errorf("the gate let the action reach the record: %+v", entries)
	}
}

// Only the machine ceiling (prepare/harden) and the systemd recorder (snapshot) may
// run as root; everything else is refused as bare root and must run as the steward user.
func TestNeedsStewardUser(t *testing.T) {
	cases := []struct {
		scope Scope
		want  bool
	}{
		{ScopeRoot, false},   // prepare / harden — mutate the machine
		{ScopeSystem, false}, // snapshot — machine-invoked recorder (root until rootless Podman)
		{ScopeOperate, true}, // deploy / lifecycle
		{ScopeObserve, true}, // status / logs / doctor
		{ScopeGrant, true},   // authorize / revoke
	}
	for _, c := range cases {
		if got := needsStewardUser(c.scope); got != c.want {
			t.Errorf("needsStewardUser(%q) = %v, want %v", c.scope, got, c.want)
		}
	}
}

// One steward per box: where a steward account exists, non-ceiling commands run as
// exactly that uid — any other user (root included) gets state in the wrong home, a
// ghost install. Off-box (no account), only bare root is refused.
func TestWrongUser(t *testing.T) {
	const steward = 990
	cases := []struct {
		name    string
		scope   Scope
		euid    int
		found   bool
		refused bool
	}{
		{"steward user runs operate", ScopeOperate, steward, true, false},
		{"root refused where account exists", ScopeOperate, 0, true, true},
		{"other user refused where account exists", ScopeObserve, 1000, true, true},
		{"ceiling always allowed as root", ScopeRoot, 0, true, false},
		{"system recorder allowed as root", ScopeSystem, 0, true, false},
		{"off-box: root refused", ScopeOperate, 0, false, true},
		{"off-box: any non-root user allowed", ScopeOperate, 1000, false, false},
	}
	for _, c := range cases {
		if got := wrongUser(c.scope, c.euid, steward, c.found); got != c.refused {
			t.Errorf("%s: wrongUser = %v, want %v", c.name, got, c.refused)
		}
	}
}

// A flag the command doesn't declare is refused, never silently dropped —
// `deploy web --por 9000` must fail, not deploy on the default port.
func TestUnknownFlag(t *testing.T) {
	deploy, _ := Lookup("deploy")
	status, _ := Lookup("status")
	cases := []struct {
		cmd  Command
		args []string
		want string
	}{
		{deploy, []string{"web", "--image", "img@sha256:e000000000000000000000000000000000000000000000000000000000000000", "--port", "9000"}, ""},
		{deploy, []string{"web", "--por", "9000"}, "--por"},
		{deploy, []string{"web", "--image=img", "--hleath", "/up"}, "--hleath"},
		{status, nil, ""},
		{status, []string{"--verbose"}, "--verbose"},
	}
	for _, c := range cases {
		if got := unknownFlag(c.cmd, c.args); got != c.want {
			t.Errorf("unknownFlag(%s, %v) = %q, want %q", c.cmd.Name, c.args, got, c.want)
		}
	}
}

// bad_args always carries the synopsis — error text and help text are the same
// string, so they cannot drift. Other codes pass through untouched.
func TestWithUsage(t *testing.T) {
	deploy, _ := Lookup("deploy")
	res := withUsage(deploy, Result{Code: "bad_args", Message: "missing <app>"})
	if !strings.Contains(res.Message, "usage: steward deploy <app>") {
		t.Errorf("bad_args did not gain the synopsis: %q", res.Message)
	}
	res = withUsage(deploy, Result{Code: "ok", Message: "deployed"})
	if strings.Contains(res.Message, "usage:") {
		t.Errorf("non-bad_args gained a synopsis: %q", res.Message)
	}
}

// Scoped writes are recorded before they run (invariant 2); reads are not. `harden
// --check` is a read and must stay off the record (it runs before the floor exists).
func TestRecordable(t *testing.T) {
	cases := []struct {
		name string
		args []string
		want bool
	}{
		{"harden", nil, true},                  // apply — a real action
		{"harden", []string{"--check"}, false}, // a read — not recorded
		{"prepare", nil, true},
		{"deploy", []string{"web"}, true},
		{"authorize", nil, true},
		{"status", nil, false},   // observe — never recorded
		{"snapshot", nil, false}, // system recorder — writes the status lane, not the chain
	}
	for _, c := range cases {
		cmd, ok := Lookup(c.name)
		if !ok {
			t.Fatalf("unknown command %q", c.name)
		}
		if got := recordable(cmd, c.args); got != c.want {
			t.Errorf("recordable(%q, %v) = %v, want %v", c.name, c.args, got, c.want)
		}
	}
}
