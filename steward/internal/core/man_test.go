package core

import (
	"strings"
	"testing"
)

// The man page is a projection of the commands table — every command must appear,
// and the roff skeleton must be present. Coverage is structural: add a command and
// this fails until the page (automatically) carries it.
func TestWriteManCoversEveryCommand(t *testing.T) {
	var b strings.Builder
	writeMan(&b)
	page := b.String()

	for _, want := range []string{".TH STEWARD 1", ".SH NAME", ".SH SYNOPSIS", ".SH COMMANDS", ".SH FILES", ".SH EXIT STATUS"} {
		if !strings.Contains(page, want) {
			t.Errorf("man page missing %q", want)
		}
	}
	for _, c := range Commands {
		if !strings.Contains(page, ".B steward "+manEscape(c.Name)) {
			t.Errorf("man page missing command %q", c.Name)
		}
	}
}

// Dashes must be escaped (\-) so flags copy-paste correctly; an unescaped "--flag"
// in output would render as a typographic dash.
func TestManEscape(t *testing.T) {
	if got := manEscape("--remove-apps"); got != `\-\-remove\-apps` {
		t.Errorf("manEscape = %q", got)
	}
}
