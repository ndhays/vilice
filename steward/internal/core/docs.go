package core

// The documentation site's seam. `steward _commands` (internal, like _exec and
// _man) writes the commands table as JSON, and every entry carries the exact page
// `steward <name> --help` prints — produced by commandHelp, not by a second
// renderer. The site prints that text verbatim, so there is no description of the
// CLI anywhere but the CLI. See decisions/help-is-the-documentation.md.

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"
)

// CommandDoc is one command as the documentation site needs it: enough to build
// the index and the sidebar, plus the rendered help page itself.
type CommandDoc struct {
	Name    string `json:"name"`
	Scope   string `json:"scope"`
	Group   string `json:"group"`
	Summary string `json:"summary"`
	Usage   string `json:"usage"`
	// Section is the coarser grouping above Group: who runs this — root, the
	// steward user, or systemd. The site heads each run of groups with it.
	Section string `json:"section"`
	// Recorded is invariant 2's answer for this verb: does an entry get written
	// before it runs? The site badges it, the help page prints it in words.
	Recorded bool `json:"recorded"`
	// Help is the page, verbatim — the same bytes a terminal gets.
	Help string `json:"help"`
}

// CommandDocs is the whole table, in the order `steward help` shows it: by group,
// and within a group in registration order.
func CommandDocs() []CommandDoc {
	docs := make([]CommandDoc, 0, len(Commands))
	for _, g := range Groups {
		for _, c := range Commands {
			if c.Scope != g.Scope {
				continue
			}
			var help strings.Builder
			commandHelp(&help, c)
			docs = append(docs, CommandDoc{
				Name:     c.Name,
				Scope:    string(c.Scope),
				Group:    g.Title,
				Section:  g.Section,
				Summary:  c.Summary,
				Usage:    synopsis(c),
				Recorded: recordable(c, nil),
				Help:     help.String(),
			})
		}
	}
	return docs
}

func writeCommandsJSON(w io.Writer) error {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(CommandDocs())
}

// CheckDocs reports every way the registered command table falls short of being
// publishable: a verb with no paragraph, a flag with no description, a synopsis
// offering a flag the gate would refuse, a line too wide for the block the site
// renders it in. Empty means the table is fit to publish.
//
// It lives here rather than in a test because it has to run against two different
// registrations — the core's tests use a fake app layer on purpose, so the only
// place the *shipped* surface exists is the assembled binary. One checker, called
// from both, beats two copies that drift.
func CheckDocs() []string {
	var problems []string
	note := func(format string, a ...any) {
		problems = append(problems, fmt.Sprintf(format, a...))
	}

	for _, c := range Commands {
		if c.Summary == "" {
			note("%s: no summary", c.Name)
		}
		// Even snapshot, which nobody types, owes a paragraph: it still appears in
		// `help` and on the site, and "systemd calls this" is worth saying once.
		if c.Long == "" {
			note("%s: no Long — every command owes the reader a paragraph", c.Name)
		}
		for _, f := range c.Flags {
			if f.What == "" {
				note("%s: --%s has no description", c.Name, f.Name)
			}
		}
		for i, ex := range c.Examples {
			if ex.Cmd == "" || ex.What == "" {
				note("%s: example %d is missing its command or its point", c.Name, i)
			}
		}
		// A synopsis that offers a flag the command does not declare tells the
		// reader to type something the gate will refuse.
		for _, token := range strings.Fields(strings.NewReplacer(
			"[", " ", "]", " ", "|", " ", "(", " ", ")", " ").Replace(c.Usage)) {
			if name := strings.TrimPrefix(token, "--"); name != token && !declares(c, name) {
				note("%s: synopsis offers --%s but the command does not declare it", c.Name, name)
			}
		}
		// The page has to fit. An overrun is not cosmetic: the site prints this
		// text in a fixed-width block, so a long line is a horizontal scrollbar on
		// every visitor's screen.
		var page strings.Builder
		commandHelp(&page, c)
		for i, line := range strings.Split(page.String(), "\n") {
			if n := len([]rune(line)); n > HelpWidth {
				note("%s: help line %d is %d columns (max %d): %s", c.Name, i+1, n, HelpWidth, line)
			}
		}
	}
	return problems
}
