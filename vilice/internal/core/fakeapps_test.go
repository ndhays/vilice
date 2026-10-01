package core

import (
	"io"
	"os"
	"testing"
)

// The core dispatches to the app layer but must not depend on that particular one —
// that is the whole point of the line. So the core's own tests register a *fake* app
// layer rather than the real internal/app.
//
// This is stronger than testing against the shipped verbs, not weaker: the gate, the
// scope ladder, and the record-before-act rule have to hold for whatever the far side
// contributes. Testing them against the real app layer would only ever prove they
// hold for the real app layer.
//
// The verbs below mirror the *shapes* the core cares about — an app-taking operate
// verb, a plain observe verb, a systemd-invoked one — not the app layer's behavior.
// None of them do anything: reaching a Run body would mean the gate let something
// through, and every test here is about what happens before that.
type fakeApps struct{}

func (fakeApps) Verbs() []Command {
	noop := func([]string) Result { return OK("") }
	appVerb := func(name, usage string) Command {
		return Command{Name: name, Scope: ScopeOperate, Summary: "fake " + name,
			Long: "A fake " + name + ", contributed by the fake app layer.", Usage: usage, Run: noop}
	}
	deploy := appVerb("deploy", "<app> --image <ref> [--port <n>] [--hostname <host>]")
	deploy.Flags = []Flag{
		{Name: "image", Arg: "<ref>", What: "fake image"},
		{Name: "port", Arg: "<n>", What: "fake port"},
		{Name: "hostname", Arg: "<host>", What: "fake hostname"},
		{Name: "health", Arg: "<path>", What: "fake health"},
	}
	backup := appVerb("backup", "<app> | --all")
	backup.Flags = []Flag{{Name: "all", What: "fake all"}}
	return []Command{
		deploy,
		appVerb("rollback", "<app>"),
		appVerb("start", "<app>"),
		appVerb("stop", "<app>"),
		appVerb("restart", "<app>"),
		appVerb("remove", "<app>"),
		backup,
		appVerb("restore", "<app>"),
		{Name: "status", Scope: ScopeObserve, Summary: "fake status",
			Long: "A fake status, contributed by the fake app layer.", Run: noop},
		{Name: "logs", Scope: ScopeObserve, Summary: "fake logs", Usage: "<app> [--tail <n>]",
			Long:  "A fake logs, contributed by the fake app layer.",
			Flags: []Flag{{Name: "tail", Arg: "<n>", What: "fake tail"}}, Run: noop},
		{Name: "snapshot", Scope: ScopeSystem, Summary: "fake snapshot",
			Long: "A fake snapshot, contributed by the fake app layer.", Run: noop},
	}
}

func (fakeApps) Substrate(string) Substrate   { return Substrate{} }
func (fakeApps) Prepare(string) error         { return nil }
func (fakeApps) Inventory() ([]string, error) { return nil, nil }
func (fakeApps) TeardownNote(io.Writer)       {}

func TestMain(m *testing.M) {
	Register(fakeApps{})
	os.Exit(m.Run())
}
