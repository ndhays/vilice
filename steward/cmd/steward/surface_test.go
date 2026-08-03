package main

import (
	"strings"
	"testing"

	"steward/internal/core"
	"steward/internal/pack/app"
)

// The core's own tests run against a fake pack on purpose — the gate must hold for
// whatever registers. That leaves one thing only the assembled binary can prove:
// that this is the surface we actually ship, and that drawing the core/pack line
// did not quietly drop a verb on the floor.
func TestAssembledSurface(t *testing.T) {
	core.Register(app.New())

	want := []string{
		// core — the trust model's own verbs
		"harden", "prepare", "uninstall", "authorize", "revoke",
		"apply-updates", "verify", "record", "actors", "packs",
		// steward-app
		"deploy", "rollback", "start", "stop", "restart", "remove",
		"backup", "restore", "registry-login", "registry-logout",
		"status", "logs", "doctor", "snapshot",
	}
	for _, name := range want {
		if _, ok := core.Lookup(name); !ok {
			t.Errorf("the assembled binary is missing %q", name)
		}
	}
	if len(core.Commands) != len(want) {
		t.Errorf("assembled table has %d commands, want %d — a verb was added or lost without updating this test",
			len(core.Commands), len(want))
	}

	// Guard the guard: the <app> synopsis convention is what the core's app-name
	// gate keys off, so if it ever stopped matching, the gate would silently cover
	// nothing on the real verbs.
	appTaking := 0
	for _, c := range core.Commands {
		if strings.Contains(c.Usage, "<app>") {
			appTaking++
		}
	}
	if appTaking < 8 {
		t.Errorf("only %d shipped commands look app-taking — has the <app> synopsis convention changed?", appTaking)
	}
}
