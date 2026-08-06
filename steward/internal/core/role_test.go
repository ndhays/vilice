package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRoleAbsentIsNotAnError(t *testing.T) {
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
	if got := Role(); got != "" {
		t.Errorf("Role() = %q on an unprepared box, want empty", got)
	}
}

func TestSetAndReadRole(t *testing.T) {
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
	if err := SetRole(RoleHost); err != nil {
		t.Fatal(err)
	}
	if got := Role(); got != RoleHost {
		t.Errorf("Role() = %q, want %q", got, RoleHost)
	}
}

// Re-running prepare with the same role is normal — it converges, like the rest of it.
func TestSetRoleIsIdempotent(t *testing.T) {
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
	for range 3 {
		if err := SetRole(RoleBalancer); err != nil {
			t.Fatalf("re-stating the same role should converge: %v", err)
		}
	}
	if got := Role(); got != RoleBalancer {
		t.Errorf("Role() = %q, want %q", got, RoleBalancer)
	}
}

// Converting a host that may be running apps into a balancer by re-running one command
// is exactly the silent surprise this refuses.
func TestSetRoleRefusesAChange(t *testing.T) {
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
	if err := SetRole(RoleHost); err != nil {
		t.Fatal(err)
	}
	err := SetRole(RoleBalancer)
	if err == nil {
		t.Fatal("changing role should be refused")
	}
	if !strings.Contains(err.Error(), "prepared as a host") {
		t.Errorf("the error should name what the box already is, got %q", err)
	}
	if got := Role(); got != RoleHost {
		t.Errorf("a refused change must not alter the role: got %q", got)
	}
}

func TestSetRoleRefusesUnknown(t *testing.T) {
	t.Setenv("STEWARD_ROLE_FILE", filepath.Join(t.TempDir(), "role"))
	if err := SetRole("database"); err == nil {
		t.Error("an unknown role should be refused")
	}
	if got := Role(); got != "" {
		t.Errorf("nothing should have been written, got %q", got)
	}
}

// A corrupt or hand-edited file reads as unprepared rather than as some third state.
func TestGarbageRoleFileReadsAsUnprepared(t *testing.T) {
	path := filepath.Join(t.TempDir(), "role")
	t.Setenv("STEWARD_ROLE_FILE", path)
	if err := os.WriteFile(path, []byte("nonsense\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := Role(); got != "" {
		t.Errorf("Role() = %q, want empty for an unrecognised value", got)
	}
}

func TestValidRole(t *testing.T) {
	for _, r := range Roles {
		if !ValidRole(r) {
			t.Errorf("ValidRole(%q) = false", r)
		}
	}
	for _, r := range []string{"", "Host", "worker", "database"} {
		if ValidRole(r) {
			t.Errorf("ValidRole(%q) = true", r)
		}
	}
}

// Both roles serve web today, but the ports come from the role so a future role that
// serves nothing can decline them without becoming a special case.
func TestRolePorts(t *testing.T) {
	for _, r := range Roles {
		if got := rolePorts(r); len(got) != 2 || got[0] != 80 || got[1] != 443 {
			t.Errorf("rolePorts(%q) = %v, want [80 443]", r, got)
		}
	}
	if got := rolePorts("nonesuch"); got != nil {
		t.Errorf("rolePorts(unknown) = %v, want nil", got)
	}
}

func TestRoleFromArgs(t *testing.T) {
	for _, in := range Roles {
		got, err := roleFromArgs([]string{in})
		if err != nil || got != in {
			t.Errorf("roleFromArgs(%q) = %q, %v", in, got, err)
		}
	}
	// Flags follow the role.
	if got, err := roleFromArgs([]string{RoleHost, "--yes"}); err != nil || got != RoleHost {
		t.Errorf("roleFromArgs(host --yes) = %q, %v", got, err)
	}
	// A flag *before* the role is refused rather than silently swallowing it: ParseArgs
	// would take the role as the flag's value and prepare nothing.
	_, err := roleFromArgs([]string{"--yes", RoleHost})
	if err == nil || !strings.Contains(err.Error(), "role comes first") {
		t.Errorf("a leading flag should be refused with guidance, got %v", err)
	}

	// Bare prepare is refused, and the message says what to type.
	_, err = roleFromArgs(nil)
	if err == nil || !strings.Contains(err.Error(), "what this box is for") {
		t.Errorf("bare prepare should be refused with guidance, got %v", err)
	}
	// An unknown role names itself and the alternatives, rather than a bare "invalid".
	_, err = roleFromArgs([]string{"database"})
	if err == nil || !strings.Contains(err.Error(), `"database"`) || !strings.Contains(err.Error(), RoleHost) {
		t.Errorf("an unknown role should name itself and the options, got %v", err)
	}
}
