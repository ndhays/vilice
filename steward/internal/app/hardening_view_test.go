package app

// Split out of the core when the core/app line was drawn: these assert
// properties of what this layer renders and writes to the box, so they belong
// with the code that renders it. The assertions are unchanged.

import (
	"os"
	"path/filepath"
	"testing"
)

// Observe reads the published fact; an absent file means "never checked", not an error.
func TestCollectHardening(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hardening.json")
	t.Setenv("STEWARD_HARDENING", path)

	if _, ok := collectHardening(); ok {
		t.Error("absent hardening file should report ok=false")
	}

	body := `{"ssh_root_login_disabled":true,"password_auth_disabled":true,` +
		`"firewall_active":true,"fail2ban_active":true,"unattended_upgrades":true,` +
		`"checked_at":"2026-06-10T00:00:00Z"}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	p, ok := collectHardening()
	if !ok {
		t.Fatal("present hardening file should report ok=true")
	}
	if !p.Hardened() || p.CheckedAt != "2026-06-10T00:00:00Z" {
		t.Errorf("unexpected posture: %+v", p)
	}
}

// status surfaces the hardening fact when present, and omits it when absent.
func TestStatusIncludesHardening(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hardening.json")
	t.Setenv("STEWARD_HARDENING", path)

	if _, present := statusCmd(nil).Data.(map[string]any)["hardening"]; present {
		t.Error("status should omit hardening when the fact is absent")
	}

	body := `{"ssh_root_login_disabled":true,"password_auth_disabled":true,` +
		`"firewall_active":true,"fail2ban_active":true,"unattended_upgrades":true}`
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, present := statusCmd(nil).Data.(map[string]any)["hardening"]; !present {
		t.Error("status should include hardening when the fact is present")
	}
}
