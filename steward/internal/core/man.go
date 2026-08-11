package core

// The man page is generated from the same commands table that renders `help` and
// usage errors — one source, three views (help, errors, man), so the page cannot
// drift. `steward _man` (internal, like _exec) writes roff to stdout; `make man`
// captures it as steward.1.

import (
	"fmt"
	"io"
	"strings"
)

// manEscape guards roff source: backslashes are escapes, and man convention
// renders literal dashes as \- (so flags copy-paste correctly).
func manEscape(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, "-", `\-`)
	return s
}

// manCommand writes one command's entry: the synopsis (with any alternate forms),
// the summary, the paragraph, its flags, and its examples. It renders the same
// fields commandHelp does, so the man page carries the whole page rather than a
// thinner version of it — one source, three views, all three the same depth.
func manCommand(w io.Writer, c Command) {
	lines := strings.Split(c.Usage, "\n")
	head := strings.TrimSpace(c.Name + " " + strings.TrimSpace(lines[0]))
	fmt.Fprintln(w, ".TP")
	fmt.Fprintf(w, ".B steward %s\n", manEscape(head))
	fmt.Fprintf(w, "%s.\n", manEscape(c.Summary))
	for _, alt := range lines[1:] {
		fmt.Fprintln(w, ".br")
		fmt.Fprintf(w, "Or: %s\n", manEscape(strings.TrimSpace(alt)))
	}

	// The body nests under the command it belongs to: one .RS around the lot, so a
	// paragraph doesn't fall back to the section indent and read as if it applied
	// to the whole group.
	fmt.Fprintln(w, ".RS")

	// Blank lines separate paragraphs in Long; roff needs .PP between them. An
	// indented line is a literal block (a role list, a JSON shape) and is set
	// no-fill so it keeps its shape.
	for _, para := range strings.Split(strings.TrimSpace(c.Long), "\n\n") {
		literal := strings.HasPrefix(para, " ")
		fmt.Fprintln(w, ".PP")
		if literal {
			fmt.Fprintln(w, ".nf")
		}
		fmt.Fprintf(w, "%s\n", manEscape(strings.TrimRight(para, "\n")))
		if literal {
			fmt.Fprintln(w, ".fi")
		}
	}

	for _, f := range c.Flags {
		fmt.Fprintln(w, ".TP")
		fmt.Fprintf(w, ".B %s\n", manEscape(flagSpec(f)))
		fmt.Fprintf(w, "%s\n", manEscape(f.What))
	}

	for _, ex := range c.Examples {
		fmt.Fprintf(w, ".PP\n%s\n", manEscape(ex.What))
		fmt.Fprintln(w, ".RS")
		fmt.Fprintln(w, ".nf")
		fmt.Fprintf(w, "%s\n", manEscape(ex.Cmd))
		fmt.Fprintln(w, ".fi")
		fmt.Fprintln(w, ".RE")
	}

	fmt.Fprintln(w, ".RE")
}

func writeMan(w io.Writer) {
	fmt.Fprintf(w, ".TH STEWARD 1 \"\" \"steward v%s\" \"Steward Manual\"\n", Version)

	fmt.Fprintln(w, `.SH NAME
steward \- accountable app hosting on one Linux box
.SH SYNOPSIS
.B steward
[\fB\-\-json\fR] \fIcommand\fR [\fIargs\fR]
.br
.B steward
help [\fIcommand\fR] | version
.SH DESCRIPTION
Steward deploys apps as containers, routes traffic to them, and keeps the record
of what happened, on the box itself. Every caller is a named actor with a declared
scope, carried by SSH keys pinned to a forced command; every state change writes
an append\-only, hash\-chained record entry \fIbefore\fR it runs.
.PP
There is no daemon, no listener, and no token: sshd invokes steward for scoped
callers, systemd invokes it on a timer, and it exists only while a command runs.
Steward is a gate and a scribe, not a runtime \(em apps are ordinary Quadlet units
under systemd behind Caddy, so deleting steward stops nothing that is running.
.SH COMMANDS`)

	// The same sections and groups, in the same order, as `steward help` and the
	// docs site. A section heads its run of groups once, as an .SS; the groups sit
	// under it as .TP-led runs, since roff has only the two subsection levels.
	section := ""
	for _, g := range Groups {
		if g.Section != section {
			section = g.Section
			fmt.Fprintf(w, ".SS %s\n", manEscape(strings.ToUpper(section)))
		}
		fmt.Fprintf(w, ".PP\n\\fB%s\\fR\n", manEscape(g.Title))
		for _, c := range Commands {
			if c.Scope == g.Scope {
				manCommand(w, c)
			}
		}
	}

	fmt.Fprintln(w, `.SH SCOPES
A higher scope grants the ones below it: observe < operate < grant. The root
ceiling sits outside the ladder \(em reachable by no scoped key. No scope
grants a shell.`)
	for _, s := range []Scope{ScopeRoot, ScopeGrant, ScopeOperate, ScopeObserve, ScopeSystem} {
		fmt.Fprintln(w, ".TP")
		fmt.Fprintf(w, ".B %s\n", s)
		line := scopeLine(s)
		if i := strings.Index(line, "— "); i >= 0 {
			line = line[i+len("— "):] // the name is the .B tag; keep the description
		}
		fmt.Fprintf(w, "%s.\n", manEscape(line))
	}

	fmt.Fprintln(w, `.SH FILES
.TP
.I /var/lib/steward/record.log
The accountable record: append\-only (chattr +a), hash\-chained. The box's history.
.TP
.I /var/lib/steward/
App specs, status snapshots, backup config, and the secrets dir (0700).
.TP
.I ~steward/.ssh/authorized_keys
The rights ledger: one forced\-command line per named actor, readable at a glance.
.TP
.I /etc/caddy/steward/
Per\-app Caddy route fragments, imported by the base Caddyfile.
.TP
.I /etc/systemd/system/steward\-snapshot.timer
The recording heartbeat (no resident daemon; systemd provides residency).
.TP
.I /etc/sudoers.d/steward
The steward user's one narrow root escalation: applying OS updates.
.SH EXIT STATUS
0 on success; 1 on failure (with \fB\-\-json\fR, a structured {code, retryable}
result on stdout); 2 on a usage error.
.SH SEE ALSO
.UR https://steward.agoraforge.org
The Steward documentation
.UE`)
}
