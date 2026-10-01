package core

// The gate, tested by walking the commands table rather than by naming commands one
// at a time. A guard written for one command and forgotten for its five siblings is
// how every validation gap in this package has started, so these tests derive their
// cases from `commands` — add a command and it is covered the same day.
//
// The companion to this file is inject_test.go, which does the same for the strings
// vilice renders into config files.

import (
	"testing"
)

// hostileAppNames are the names that must never reach a filesystem path or a systemd
// unit name. Traversal is the sharp one: an app name is concatenated into
// <apps>/<name>.json and <quadlet>/<name>-<color>.container.
var hostileAppNames = []string{
	"../victim",
	"../../etc/passwd",
	"..",
	"a/b",
	"/absolute",
	"name with spaces",
	"semi;colon",
	"new\nline",
	"dot.dot",
	"tilde~",
	"$(whoami)",
	"quote\"quote",
	"null\x00byte",
	// Argv shapes: a name that a tool would read as a flag rather than a name, which is
	// injection with no shell in it (`systemctl --user stop -H…`). A `--`-prefixed word is
	// not here because ParseArgs takes it for a flag, so it never reaches the app slot at
	// all — the command answers "missing <app>" instead.
	"-v",
	"-H",
	"-",
}

// Every command that takes an <app> refuses a hostile name at the door, before it is
// recorded and before it runs. Derived from the commands table: a new app-taking
// command is covered without touching this test.
func TestEveryAppCommandRefusesHostileNames(t *testing.T) {
	var appCommands []Command
	for _, c := range Commands {
		if takesAppArg(c) {
			appCommands = append(appCommands, c)
		}
	}
	// Guard the guard: if the synopsis convention ever changes, this test would
	// silently cover nothing.
	if len(appCommands) < 8 {
		t.Fatalf("only %d commands look app-taking — has the <app> synopsis convention changed?", len(appCommands))
	}

	for _, c := range appCommands {
		t.Run(c.Name, func(t *testing.T) {
			for _, name := range hostileAppNames {
				if got := badAppArg(c, []string{name}); got == "" {
					t.Errorf("accepted app name %q", name)
				}
			}
			// And the refusal happens ahead of the record, so it never reached the
			// action — one full pass through the door is enough to prove the wiring.
			path := useTempRecord(t)
			if code := enter(c, []string{"../victim"}, "ci", true, nonRootUID); code != 1 {
				t.Errorf("exit %d, want 1", code)
			}
			assertRecordEmpty(t, path)
		})
	}
}

// A valid name is still accepted — the guard must not have closed the door entirely.
func TestValidAppNamesStillPass(t *testing.T) {
	for _, name := range []string{"web", "web-2", "my_app", "A1"} {
		if !ValidAppName(name) {
			t.Errorf("validAppName(%q) = false, want true", name)
		}
		for _, c := range Commands {
			if takesAppArg(c) && badAppArg(c, []string{name}) != "" {
				t.Errorf("%s refused valid app name %q", c.Name, name)
			}
		}
	}
}

// The scope ladder is a claim about reachability: observe ⊂ operate ⊂ ssh, and an
// operate key must not be able to promote itself. Both routes it had ran through a file
// vilice writes on its behalf — a bind mount, and a restic restore — so the property
// is that no path an operate key can declare reaches the files that confer privilege.
//

// The two checks are deliberately different, and this is the difference.
//
// Where a bind mount may point is **policy**: enforced where a spec enters the box, so
// a hostile one can't be introduced. Whether a value can end its own line is **rendering
// safety**: enforced everywhere, including on state read back off disk.
//
