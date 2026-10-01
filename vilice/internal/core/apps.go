package core

import (
	"fmt"
	"io"
)

// Apps is the app layer's side of the one line drawn inside this binary: the core
// owns the gate, the record, and the ceiling; the app layer owns what a verb
// actually does on the box.
//
// There is exactly one implementation (internal/app) and it is wired in at compile
// time by cmd/vilice. Nothing is discovered, nothing is loaded, and the interface
// is not an extension point — it is the line, written down where the compiler can
// hold us to it. Vilice once had a plugin layer here; it was dropped because the
// far side of the seam was permanently empty. See decisions/roles-not-packs.md.
type Apps interface {
	// Verbs are the commands the app layer contributes to the dispatch table.
	Verbs() []Command

	// Substrate is what running apps needs installed on the box *for this role*,
	// declared so the ceiling can show it and ask once before anything is
	// installed. A balancer that carried a container runtime it would never use
	// would be surface to patch for no benefit.
	Substrate(role string) Substrate

	// Prepare installs that substrate and configures it, for this role. `prepare`
	// calls it as root, after the accountability floor is laid, so it can rely on
	// the _vilice account and the record already existing.
	Prepare(role string) error

	// Inventory is what the app layer has placed on this box, by name. The ceiling
	// needs it to tell an operator what `uninstall` is about to affect, without
	// knowing what any of it is.
	Inventory() ([]string, error)

	// TeardownNote writes what this layer leaves on the box, and what an operator
	// must know about it before vilice goes — the last moment the box can say it.
	// `uninstall` renders it under its own "This keeps:" list, so it writes bullets
	// ("  - ...") and nothing else.
	//
	// This is the seam for *every* such line, rather than one method per message.
	// The ceiling removes the gate and the scribe and no more, so it has nothing of
	// its own to say here — and a ceiling that recited the substrate from memory
	// told a balancer it was keeping a container runtime it never installed.
	//
	// It prints where a secret lives, never the secret: uninstall keeps
	// /var/lib/vilice, so the file is still there for whoever needs it, and
	// printing it would spend it into terminal scrollback, the journal, and the log
	// of any automation that ran with --yes.
	TeardownNote(w io.Writer)
}

// Substrate is what the app layer needs on the box before its verbs can work. The
// ceiling shows it and asks the operator once — so consent covers everything that is
// about to be installed, including anything apt cannot simulate.
type Substrate struct {
	// Packages are apt packages, used both for the prompt and for apt's dry run.
	Packages []string
	// Note is anything else the operator is agreeing to that Packages does not
	// convey — a third-party apt repo, say. Shown at the prompt, not after it.
	Note string
}

// apps is the registered app layer, or nil in a core-only build.
var apps Apps

// Register admits the app layer's verbs to the dispatch table. Every verb still
// enters through the same door: Register only adds names the gate will check,
// record, and then run — it grants no path around any of that.
//
// A verb may not take a name that is already claimed. Lookup returns the first
// match, so a duplicate would not override anything — it would sit in the table
// unreachable, listed by `help` and named in the man page, and an operator would
// have no way to tell which one a scoped key just invoked. A verb that cannot be
// identified from its name cannot be accountable, so this is refused loudly at
// wiring time rather than resolved by an arbitrary rule.
func Register(a Apps) {
	for _, v := range a.Verbs() {
		if existing, taken := Lookup(v.Name); taken {
			panic(fmt.Sprintf("the app layer registers %q, which is already claimed (scope %s)",
				v.Name, existing.Scope))
		}
		Commands = append(Commands, v)
	}
	apps = a
}
