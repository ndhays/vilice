package core

import (
	"testing"
)

func TestParseHardening(t *testing.T) {
	// check.sh emits exactly this shape.
	in := []byte(`{"ssh_root_login_disabled":true,"password_auth_disabled":true,` +
		`"firewall_active":true,"fail2ban_active":false,"unattended_upgrades":true,` +
		`"open_ports":"22,80,443"}`)
	p, err := ParseHardening(in)
	if err != nil {
		t.Fatalf("parseHardening: %v", err)
	}
	if !p.SSHRootLoginDisabled || !p.PasswordAuthDisabled || !p.FirewallActive || !p.UnattendedUpgrades {
		t.Errorf("expected those four true, got %+v", p)
	}
	if p.Fail2banActive {
		t.Errorf("fail2ban should be false, got %+v", p)
	}
	if p.OpenPorts != "22,80,443" {
		t.Errorf("open_ports = %q, want 22,80,443", p.OpenPorts)
	}
	if _, err := ParseHardening([]byte("not json")); err == nil {
		t.Error("expected an error on malformed JSON")
	}
}

func TestHardeningDrift(t *testing.T) {
	full := HardeningPosture{
		SSHRootLoginDisabled: true, PasswordAuthDisabled: true,
		FirewallActive: true, Fail2banActive: true, UnattendedUpgrades: true,
	}
	if !full.Hardened() {
		t.Errorf("a fully-hardened posture should report hardened(); drift = %v", full.Drift())
	}
	if d := full.Drift(); len(d) != 0 {
		t.Errorf("expected no drift, got %v", d)
	}

	drifted := full
	drifted.SSHRootLoginDisabled = false
	drifted.FirewallActive = false
	if drifted.Hardened() {
		t.Error("a drifted posture should not report hardened()")
	}
	d := drifted.Drift()
	if len(d) != 2 {
		t.Fatalf("expected 2 drift items, got %v", d)
	}
	if d[0] != "root SSH login enabled" || d[1] != "firewall inactive" {
		t.Errorf("drift order/text wrong: %v", d)
	}
}
