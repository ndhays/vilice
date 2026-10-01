package main

import (
	"os"
	"strings"
	"testing"

	"vilice/internal/app"
	"vilice/internal/core"
)

// Assemble the real binary's surface once: Register panics on a verb claimed twice,
// so every test here shares the one registration main() would do.
func TestMain(m *testing.M) {
	core.Register(app.New())
	os.Exit(m.Run())
}

// The core's own tests run against a fake app layer on purpose — the gate must hold
// for whatever registers. That leaves one thing only the assembled binary can prove:
// that this is the surface we actually ship, and that drawing the core/app line did
// not quietly drop a verb on the floor.
func TestAssembledSurface(t *testing.T) {
	want := []string{
		// core — the trust model's own verbs
		"harden", "prepare", "uninstall", "authorize", "revoke",
		"apply-updates", "verify", "record", "actors",
		// the app layer
		"deploy", "rollback", "start", "stop", "restart", "remove",
		"route",
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

// The documentation site is built from this table: `vilice _commands` hands it the
// rendered help page for every verb, and the site prints that text verbatim. So a
// verb shipped without a paragraph, a flag without a description, or a line too
// wide for the block it lands in is not a style problem — it is a hole in the
// published docs. This is the only place the *shipped* surface can be checked; the
// core's own copy of this test runs against a fake app layer.
func TestShippedSurfaceIsPublishable(t *testing.T) {
	for _, problem := range core.CheckDocs() {
		t.Error(problem)
	}
}
