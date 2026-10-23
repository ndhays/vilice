package core

import (
	"fmt"
	"io"
	"strings"
)

// HelpWidth is the column every help page is written to fit. Eighty is the
// terminal nobody has to widen, and it is also what makes the page publishable:
// the docs site prints this text verbatim, and a line that wraps on a phone is a
// line that reads as broken. Authors hard-wrap Long to it; nothing here reflows.
const HelpWidth = 78

// commandHelp is the per-command page: what it does, how to call it, who may, and
// whether it is written down. Reached by `vilice help <name>`, by `--help`/`-h`
// on any command, and — verbatim — by the documentation site, which renders this
// output rather than describing it a second time. See
// decisions/help-is-the-documentation.md.
func commandHelp(w io.Writer, cmd Command) {
	fmt.Fprintf(w, "vilice %s — %s\n", cmd.Name, cmd.Summary)
	if cmd.Long != "" {
		fmt.Fprintf(w, "\n%s\n", strings.TrimRight(cmd.Long, "\n"))
	}

	fmt.Fprintln(w, "\nUsage:")
	fmt.Fprintf(w, "  vilice %s\n", synopsis(cmd))

	if len(cmd.Flags) > 0 {
		fmt.Fprintln(w, "\nFlags:")
		width := flagColumn(cmd.Flags)
		indent := strings.Repeat(" ", 2+width+2)
		for _, f := range cmd.Flags {
			lines := wrap(f.What, HelpWidth-len(indent))
			fmt.Fprintf(w, "  %-*s  %s\n", width, flagSpec(f), lines[0])
			for _, line := range lines[1:] {
				fmt.Fprintf(w, "%s%s\n", indent, line)
			}
		}
	}

	// What the example is for goes above the line you would type, not beside it: a
	// command long enough to need a continuation would otherwise sit level with its
	// own description, and you could not tell which was which.
	if len(cmd.Examples) > 0 {
		fmt.Fprintln(w, "\nExamples:")
		for i, ex := range cmd.Examples {
			if i > 0 {
				fmt.Fprintln(w)
			}
			for _, line := range wrap(ex.What, HelpWidth-2) {
				fmt.Fprintf(w, "  %s\n", line)
			}
			for _, line := range strings.Split(ex.Cmd, "\n") {
				fmt.Fprintf(w, "    %s\n", line)
			}
		}
	}

	fmt.Fprintf(w, "\nScope:  %s\n", scopeLine(cmd.Scope))
	fmt.Fprintf(w, "Record: %s\n", recordLine(cmd))
}

// wrap breaks a one-line description into lines of at most width columns, so
// authors write plain sentences and the renderer owns the shape. Always returns at
// least one line. Counts runes, not bytes — the help text is full of — and ….
func wrap(s string, width int) []string {
	var lines []string
	line := ""
	for _, word := range strings.Fields(s) {
		switch {
		case line == "":
			line = word
		case len([]rune(line))+1+len([]rune(word)) <= width:
			line += " " + word
		default:
			lines = append(lines, line)
			line = word
		}
	}
	return append(lines, line)
}

// flagSpec is how a flag is typed: --name, or --name <arg>, with the short form
// ahead of it when there is one. The short form is printed rather than mentioned in
// prose, so it is documented by the same list the gate admits.
func flagSpec(f Flag) string {
	s := "--" + f.Name
	if f.Alias != "" {
		s = "-" + f.Alias + ", " + s
	}
	if f.Arg == "" {
		return s
	}
	return s + " " + f.Arg
}

// flagColumn is the width the descriptions line up at — the longest spec, unless
// that would push the text past HelpWidth, in which case the ragged line is the
// lesser evil.
func flagColumn(flags []Flag) int {
	width := 0
	for _, f := range flags {
		if n := len(flagSpec(f)); n > width {
			width = n
		}
	}
	if max := HelpWidth / 2; width > max {
		return max
	}
	return width
}

// recordLine says whether an invocation lands in the accountable record before it
// runs. Help is the natural place to answer it: invariant 2 is the whole claim, and
// a reader should not have to infer which side of it a command is on.
func recordLine(cmd Command) string {
	switch {
	case cmd.RecordNote != "":
		return cmd.RecordNote
	case recordable(cmd, nil):
		return "written before the command runs"
	}
	return "not recorded — this command reads, it does not act"
}

// scopeLine says, in one line, who may run a command — help doubling as a second
// view of the rights ladder.
func scopeLine(s Scope) string {
	switch s {
	case ScopeRoot:
		return "root — run on the box as root; never reachable over scoped SSH"
	case ScopeGrant:
		return "grant — the top rung; mints and revokes keys. No scope grants a shell"
	case ScopeOperate:
		return "operate — reachable by an operate or grant key"
	case ScopeObserve:
		return "observe — reachable by any scoped key"
	case ScopeSystem:
		return "system — systemd-invoked; not a human verb"
	}
	return string(s)
}

func usage(w io.Writer) {
	fmt.Fprintf(w, "vilice v%s — one door to this box: named, scoped, recorded\n\n", Version)
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintln(w, "  vilice [--json] <command> [args]")
	fmt.Fprintln(w, "  vilice help [command] | version")
	fmt.Fprintln(w)
	section := ""
	for _, g := range Groups {
		// The section heads its run of groups, once. Upper-cased here rather than
		// stored that way, so the string stays a sentence for the renderers that
		// want it as one — the docs site sets its own case in CSS.
		if g.Section != section {
			section = g.Section
			fmt.Fprintf(w, "%s\n\n", strings.ToUpper(section))
		}
		printGroup(w, g.Title, g.Scope)
	}
	fmt.Fprintln(w, "Run `vilice help <command>` for the full page: what it does, every")
	fmt.Fprintln(w, "flag, examples, who may run it, and whether it is recorded.")
}

// Groups are the scopes as a reader meets them: the ceiling first, then the ladder
// from the top rung down, then the verb systemd calls. One order, used by `help`,
// by the man page, and by the documentation site's command index.
//
// Section is the coarser question a reader actually arrives with — *who runs this* —
// and it is the account, not the scope: the ceiling is the operator as root, the
// ladder is all the _vilice user, and snapshot is systemd. Consecutive groups share
// a section, and every renderer prints the section once, when it changes.
var Groups = []struct {
	Section string
	Title   string
	Scope   Scope
}{
	{"Run as root", "Box commands (root)", ScopeRoot},
	{"Run as _vilice", "Authorize", ScopeGrant},
	{"Run as _vilice", "Operate", ScopeOperate},
	{"Run as _vilice", "Observe", ScopeObserve},
	{"Run by systemd", "Run by systemd", ScopeSystem},
}

func printGroup(w io.Writer, title string, s Scope) {
	fmt.Fprintf(w, "  %s:\n", title)
	for _, c := range Commands {
		if c.Scope == s {
			fmt.Fprintf(w, "    %-16s %s\n", c.Name, c.Summary)
		}
	}
	fmt.Fprintln(w)
}
