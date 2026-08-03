package app

import (
	"fmt"
	"path/filepath"
	"steward/internal/core"
	"testing"
)

func TestRunChecksReportsMissingTools(t *testing.T) {
	// Point the record dir at a real, existing temp dir so that check passes.
	dir := t.TempDir()
	t.Setenv("STEWARD_RECORD", filepath.Join(dir, "record.log"))
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

func TestParseLogsArgs(t *testing.T) {
	cases := []struct {
		args     []string
		wantApp  string
		wantTail int
	}{
		{[]string{"web"}, "web", 0},
		{[]string{"web", "-n", "50"}, "web", 50},
		{[]string{"-n", "100", "api"}, "api", 100},
		{[]string{"web", "--tail", "10"}, "web", 10},
		{[]string{}, "", 0},
	}
	for _, c := range cases {
		app, tail := parseLogsArgs(c.args)
		if app != c.wantApp || tail != c.wantTail {
			t.Errorf("parseLogsArgs(%v) = (%q, %d), want (%q, %d)", c.args, app, tail, c.wantApp, c.wantTail)
		}
	}
}
