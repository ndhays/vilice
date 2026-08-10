package core

import "testing"

// The help page is the documentation: the site prints commandHelp's output
// verbatim rather than describing the CLI a second time (see
// decisions/help-is-the-documentation.md). CheckDocs is what makes "the page is
// written, complete, and fits" a mechanism rather than a habit.
//
// Here it runs against the fake app layer, which proves the checker holds for
// whatever registers. The shipped surface is checked in cmd/steward, where the real
// one is.

func TestFakeSurfaceIsPublishable(t *testing.T) {
	for _, problem := range CheckDocs() {
		t.Error(problem)
	}
}

// Every command reaches the site, in a group the sidebar knows how to show. A verb
// whose scope is missing from Groups would vanish from `help` and from the docs at
// the same time, silently.
func TestEveryCommandLandsInAGroup(t *testing.T) {
	docs := CommandDocs()
	if len(docs) != len(Commands) {
		t.Fatalf("CommandDocs has %d entries, want %d — a scope is missing from Groups",
			len(docs), len(Commands))
	}
	for _, d := range docs {
		if d.Group == "" || d.Help == "" {
			t.Errorf("%s: empty group or help", d.Name)
		}
	}
}
