package app

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"

	"steward/internal/core"
)

// The substrate is per role, and teardown must say so. The ceiling used to recite
// "podman, caddy, restic" from memory, which is false on a balancer: it installs
// Caddy alone, so it cannot be leaving a container runtime or a backup tool behind.
// Whatever the box happens to have installed, the note names only this role's tools.
func TestBalancerTeardownNoteNamesNoRuntime(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(dir, "role"))
	t.Setenv("STEWARD_BACKUP_CONFIG", filepath.Join(dir, "absent.json"))
	if err := core.SetRole(core.RoleBalancer); err != nil {
		t.Fatal(err)
	}

	var note bytes.Buffer
	New().TeardownNote(&note)

	for _, unwanted := range []string{"podman", "restic"} {
		if strings.Contains(note.String(), unwanted) {
			t.Errorf("a balancer's teardown note names %q, which it never installed:\n%s",
				unwanted, note.String())
		}
	}
}

// A host runs apps, so it gets all three, and `prepare` installs them in the order
// the list gives. One list feeds prepare's steps, its closing report, and teardown —
// this pins what is in it.
func TestToolsPerRole(t *testing.T) {
	for role, want := range map[string][]string{
		core.RoleHost:     {"podman", "caddy", "restic"},
		core.RoleBalancer: {"caddy"},
	} {
		var got []string
		for _, tool := range tools(role) {
			got = append(got, tool.name)
		}
		if strings.Join(got, ",") != strings.Join(want, ",") {
			t.Errorf("tools(%q) = %v, want %v", role, got, want)
		}
	}
}
