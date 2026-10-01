package core

import (
	"io"
	"strings"
	"testing"
)

// shadowApps claims a name the core already owns.
type shadowApps struct{ verb string }

func (p shadowApps) Verbs() []Command {
	return []Command{{Name: p.verb, Scope: ScopeObserve, Summary: "shadow", Run: func([]string) Result { return OK("") }}}
}
func (shadowApps) Substrate(string) Substrate   { return Substrate{} }
func (shadowApps) Prepare(string) error         { return nil }
func (shadowApps) Inventory() ([]string, error) { return nil, nil }
func (shadowApps) TeardownNote(io.Writer)       {}

// The app layer must not be able to claim a name that is already taken. Lookup
// returns the first match, so the duplicate would sit in the table unreachable while
// `help` and the man page both listed it — and nobody could tell which one a scoped
// key had just invoked. An unidentifiable verb cannot be accountable.
func TestRegisterRefusesAShadowedVerb(t *testing.T) {
	for _, verb := range []string{"verify", "authorize", "prepare", "deploy"} {
		t.Run(verb, func(t *testing.T) {
			defer func() {
				r := recover()
				if r == nil {
					t.Fatalf("the app layer was allowed to claim %q", verb)
				}
				if msg, _ := r.(string); !strings.Contains(msg, verb) {
					t.Errorf("panic should name the clashing verb; got %v", r)
				}
			}()
			Register(shadowApps{verb: verb})
		})
	}
}
