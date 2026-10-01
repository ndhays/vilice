package app

import (
	"fmt"
	"path/filepath"
	"testing"
	"vilice/internal/core"
)

func TestRunChecksReportsMissingTools(t *testing.T) {
	// Point the record dir at a real, existing temp dir so that check passes.
	dir := t.TempDir()
	t.Setenv("VILICE_RECORD", filepath.Join(dir, "record.log"))
	t.Setenv(core.AuthorizedKeysEnv, filepath.Join(dir, "authorized_keys"))

	// Fake lookup: podman present, caddy missing, systemctl present.
	look := func(name string) (string, error) {
		if name == "caddy" {
			return "", fmt.Errorf("not found")
		}
		return "/usr/bin/" + name, nil
	}

	// Fake podman version: new enough for Quadlet.
	podmanVer := func() (string, error) { return "podman version 5.7.0", nil }
	checks := runChecks(look, podmanVer)
	byName := map[string]check{}
	for _, c := range checks {
		byName[c.Name] = c
	}
	if !byName["podman"].OK {
		t.Error("podman should be OK")
	}
	if byName["caddy"].OK {
		t.Error("caddy should be reported missing")
	}
	if !byName["record dir"].OK {
		t.Errorf("record dir should exist: %+v", byName["record dir"])
	}
}

// Both spellings of --tail mean the same thing. `--tail=10` used to arrive here and
// be discarded: the gate admits it (it splits on `=` to check the name is declared)
// and this had its own parser, which matched whole tokens and had no case for it. The
// reader asked for ten lines and got the entire log, silently.
//
// `-n` is not tested here any more, and that is the fix: it is declared as the flag's
// Alias and rewritten by the gate, so it never reaches this function. See
// TestNormalizeAliases in core.
func TestParseLogsArgs(t *testing.T) {
	cases := []struct {
		args     []string
		wantApp  string
		wantTail int
	}{
		{[]string{"web"}, "web", 0},
		{[]string{"web", "--tail", "10"}, "web", 10},
		{[]string{"web", "--tail=10"}, "web", 10},
		{[]string{"--tail=100", "api"}, "api", 100},
		{[]string{}, "", 0},
	}
	for _, c := range cases {
		app, tail, err := parseLogsArgs(c.args)
		if err != nil {
			t.Errorf("parseLogsArgs(%v) errored: %v", c.args, err)
			continue
		}
		if app != c.wantApp || tail != c.wantTail {
			t.Errorf("parseLogsArgs(%v) = (%q, %d), want (%q, %d)", c.args, app, tail, c.wantApp, c.wantTail)
		}
	}
}

// A tail that is not a line count is refused, not rounded down to "all of it".
// Printing the whole log because the count was a typo is the same silent wrong
// answer the parser bug gave, reached by a different road.
func TestParseLogsArgsRefusesANonCount(t *testing.T) {
	for _, args := range [][]string{
		{"web", "--tail", "lots"},
		{"web", "--tail=lots"},
		{"web", "--tail"},
		{"web", "--tail=-5"},
	} {
		if _, _, err := parseLogsArgs(args); err == nil {
			t.Errorf("parseLogsArgs(%v) accepted a non-count", args)
		}
	}
}
