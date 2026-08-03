package core

import (
	"io"
	"os"
	"testing"
)

// The core dispatches to packs but must not depend on any particular one — that is
// the whole point of the line. So the core's own tests register a *fake* pack rather
// than the real steward-app.
//
// This is stronger than testing against the shipped verbs, not weaker: the gate,
// the scope ladder, and the record-before-act rule have to hold for whatever a pack
// contributes, including one written by somebody else next year. Testing them
// against the app pack would only ever prove they hold for the app pack.
//
// The verbs below mirror the *shapes* the core cares about — an app-taking operate
// verb, a plain observe verb, a systemd-invoked one — not the app pack's behavior.
// None of them do anything: reaching a Run body would mean the gate let something
// through, and every test here is about what happens before that.
type fakePack struct{}

func (fakePack) Name() string { return "steward-fake" }

func (fakePack) Verbs() []Command {
	noop := func([]string) Result { return OK("") }
	appVerb := func(name, usage string) Command {
		return Command{Name: name, Scope: ScopeOperate, Summary: "fake " + name, Usage: usage, Run: noop}
	}
	deploy := appVerb("deploy", "<app> --image <ref> [--port <n>] [--hostname <host>] [--health <path>]")
	deploy.Flags = []string{"image", "port", "hostname", "health"}
	return []Command{
		deploy,
		appVerb("rollback", "<app>"),
		appVerb("start", "<app>"),
		appVerb("stop", "<app>"),
		appVerb("restart", "<app>"),
		appVerb("remove", "<app>"),
		appVerb("backup", "<app> | --all"),
		appVerb("restore", "<app>"),
		{Name: "status", Scope: ScopeObserve, Summary: "fake status", Run: noop},
		{Name: "logs", Scope: ScopeObserve, Summary: "fake logs", Usage: "<app> [--tail <n>]",
			Flags: []string{"tail"}, Run: noop},
		{Name: "snapshot", Scope: ScopeSystem, Summary: "fake snapshot", Run: noop},
	}
}

func (fakePack) Substrate() Substrate         { return Substrate{} }
func (fakePack) Prepare() error               { return nil }
func (fakePack) Inventory() ([]string, error) { return nil, nil }
func (fakePack) TeardownNote(io.Writer)       {}

func TestMain(m *testing.M) {
	Register(fakePack{})
	os.Exit(m.Run())
}
