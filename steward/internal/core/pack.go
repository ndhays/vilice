package core

import (
	"fmt"
	"io"
)

// A Pack is a set of verbs the core dispatches to. The core owns the gate, the
// record, and the ceiling; a pack owns what a verb actually does on the box.
//
// Packs are named by domain, not substrate — steward-backup, never steward-restic.
// The pack promises the outcome; the tool underneath is today's implementation.
// See decisions/core-and-packs.md.
//
// Packs are compiled in for now. The interface is the same one an out-of-process
// pack will satisfy, so the split later is a packaging change rather than a
// redesign.
type Pack interface {
	// Name is the pack's name as it appears in the manifest and in the record.
	Name() string

	// Verbs are the commands this pack contributes to the dispatch table.
	Verbs() []Command

	// Substrate is what the pack needs installed on the box *for this role*,
	// declared so the ceiling can show it and ask once before anything is
	// installed. A balancer that carried a container runtime it would never use
	// would be surface to patch for no benefit.
	Substrate(role string) Substrate

	// Prepare installs that substrate and configures it, for this role. `prepare`
	// calls it as root, after the accountability floor is laid, so a pack can rely
	// on the steward account and the record already existing.
	Prepare(role string) error

	// Inventory is what the pack has placed on this box, by name. The ceiling
	// needs it to tell an operator what `uninstall` is about to affect, without
	// knowing what any of it is.
	Inventory() ([]string, error)

	// TeardownNote writes what an operator must know before this pack's things
	// go — the last moment the box can say it. It prints where a secret lives,
	// never the secret: uninstall keeps /var/lib/steward, so the file is still
	// there for whoever needs it, and printing it would spend it into terminal
	// scrollback, the journal, and the log of any automation that ran with --yes.
	TeardownNote(w io.Writer)
}

// Substrate is what a pack needs on the box before its verbs can work. The ceiling
// aggregates it across packs and asks the operator once — so consent covers
// everything that is about to be installed, including anything apt cannot simulate.
type Substrate struct {
	// Packages are apt packages, used both for the prompt and for apt's dry run.
	Packages []string
	// Note is anything else the operator is agreeing to that Packages does not
	// convey — a third-party apt repo, say. Shown at the prompt, not after it.
	Note string
}

// packs are the registered packs, in registration order.
var packs []Pack

// Register admits a pack's verbs to the dispatch table. Every verb still enters
// through the same door: Register only adds names the gate will check, record,
// and then run — it grants no path around any of that.
//
// A pack may not take a name that is already claimed. Lookup returns the first
// match, so a duplicate would not override anything — it would sit in the table
// unreachable, listed by `help` and named in the man page, and an operator would
// have no way to tell which one a scoped key just invoked. A verb that cannot be
// identified from its name cannot be accountable, so this is refused loudly at
// wiring time rather than resolved by an arbitrary rule.
func Register(ps ...Pack) {
	for _, p := range ps {
		for _, v := range p.Verbs() {
			if existing, taken := Lookup(v.Name); taken {
				panic(fmt.Sprintf("pack %q registers %q, which is already claimed (scope %s)",
					p.Name(), v.Name, existing.Scope))
			}
			v.Pack = p.Name()
			Commands = append(Commands, v)
		}
		packs = append(packs, p)
	}
}

// Packs are the registered packs, for the ceiling verbs that must ask them what
// they have on the box.
func Packs() []Pack { return packs }
