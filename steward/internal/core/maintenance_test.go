package core

import (
	"strings"
	"testing"
)

func TestSudoizeAddsSudoOnlyWhenNotRoot(t *testing.T) {
	argv := []string{"apt-get", "update", "-y"}

	if got := strings.Join(sudoize(0, argv), " "); got != "apt-get update -y" {
		t.Errorf("as root: want the command unchanged, got %q", got)
	}
	if got := strings.Join(sudoize(1000, argv), " "); got != "sudo -n apt-get update -y" {
		t.Errorf("as steward: want a non-interactive sudo prefix, got %q", got)
	}
}

// The grant `prepare` lays and what apply-updates actually runs must stay in
// lockstep: every command is authorized, and the grant is narrow (no shell, no
// wildcard) — so issuing apply-updates can run exactly those two things as root.
func TestUpdateGrantMatchesWhatApplyUpdatesRuns(t *testing.T) {
	grant := sudoersForUpdates()

	if !strings.Contains(grant, StewardUser+" ALL=(root) NOPASSWD:") {
		t.Errorf("grant should be a NOPASSWD rule for %q:\n%s", StewardUser, grant)
	}
	for _, tooBroad := range []string{"/bin/sh", "/bin/bash", "*"} {
		if strings.Contains(grant, tooBroad) {
			t.Errorf("grant is too broad — contains %q:\n%s", tooBroad, grant)
		}
	}
	for _, cmd := range aptUpdateCommands() {
		want := "/usr/bin/" + strings.Join(cmd, " ")
		if !strings.Contains(grant, want) {
			t.Errorf("grant does not authorize %q:\n%s", want, grant)
		}
	}
}
