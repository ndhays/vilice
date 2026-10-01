package core

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// Flag parsing has exactly three implementations, and they all live here: ParseArgs
// (auth.go), hasFlag (provision.go), and the gate's own parseInvocation/unknownFlag
// (dispatch.go). These tests exist because a fourth one appeared once and cost a
// documented flag.
//
// `logs` had its own parser. It matched whole tokens, so `--tail 100` worked and
// `--tail=100` was silently discarded — the gate admits both spellings (it splits on
// `=` to check the name is declared), and the second arrived at a parser that had no
// case for it. The reader asked for a hundred lines and got the whole log, with no
// error anywhere. That is precisely the outcome the flag gate exists to prevent.

// Both spellings are one flag. The gate treats `--f=v` and `--f v` as the same
// declared flag, so every parser downstream of it has to as well — otherwise the gate
// admits something no command will act on.
func TestParseArgsAcceptsBothFlagSpellings(t *testing.T) {
	cases := []struct {
		name string
		args []string
	}{
		{"separate", []string{"web", "--tail", "100"}},
		{"joined", []string{"web", "--tail=100"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			flags, pos := ParseArgs(c.args)
			if flags["tail"] != "100" {
				t.Errorf("tail = %q, want \"100\"", flags["tail"])
			}
			if len(pos) != 1 || pos[0] != "web" {
				t.Errorf("positionals = %v, want [web]", pos)
			}
		})
	}
}

// A boolean flag is present or absent, and the gate refuses one given a value before
// any command sees it. The alternative was reading `--yes=1` as present, which makes
// `--yes=false` mean yes — a flag that does the opposite of what it says.
func TestBooleanFlagsTakeNoValue(t *testing.T) {
	prepare, _ := Lookup("prepare")
	for _, args := range [][]string{
		{"host", "--yes=1"},
		{"host", "--yes=false"},
		{"host", "--json=true"}, // the global read flag, in its valued spelling
	} {
		if bad := booleanWithValue(prepare, args); bad == "" {
			t.Errorf("booleanWithValue(%v) allowed a valued boolean", args)
		}
	}
	for _, args := range [][]string{
		{"host", "--yes"},
		{"host"},
	} {
		if bad := booleanWithValue(prepare, args); bad != "" {
			t.Errorf("booleanWithValue(%v) = %q, want none", args, bad)
		}
	}
	// A flag that takes a value is not a boolean, and keeps its `=` spelling.
	logs, _ := Lookup("logs")
	if bad := booleanWithValue(logs, []string{"web", "--tail=100"}); bad != "" {
		t.Errorf("--tail=100 was refused as a valued boolean (%q)", bad)
	}
}

// hasFlag stays an exact match, which is only safe because the gate above refuses the
// valued spelling. If that check ever goes, this silently starts ignoring `--yes=1`.
func TestHasFlagIsExact(t *testing.T) {
	for _, args := range [][]string{{"host", "--yes"}, {"host", "-y"}} {
		if !hasFlag(args, "-y", "--yes") {
			t.Errorf("hasFlag(%v) = false, want true", args)
		}
	}
	for _, args := range [][]string{{"host"}, {"host", "--yesplease"}, {"host", "--remove-apps"}} {
		if hasFlag(args, "-y", "--yes") {
			t.Errorf("hasFlag(%v) = true, want false", args)
		}
	}
}

// A declared short form is rewritten at the gate, so exactly one spelling reaches
// the command. This is where `-n` lives now — `logs` used to handle it itself, which
// is how it came to have a second flag parser at all.
func TestNormalizeAliases(t *testing.T) {
	cmd := Command{Name: "logs", Flags: []Flag{{Name: "tail", Alias: "n", Arg: "<n>"}}}
	cases := []struct {
		in, want []string
	}{
		{[]string{"web", "-n", "50"}, []string{"web", "--tail", "50"}},
		{[]string{"web", "-n=50"}, []string{"web", "--tail=50"}},
		{[]string{"web", "--tail", "50"}, []string{"web", "--tail", "50"}},
		// An app may legally be named with a leading dash-free string only, but a
		// near-miss must not be swept up: only the exact short form is rewritten.
		{[]string{"-nope"}, []string{"-nope"}},
		{[]string{"web"}, []string{"web"}},
	}
	for _, c := range cases {
		got := normalizeAliases(cmd, c.in)
		if strings.Join(got, " ") != strings.Join(c.want, " ") {
			t.Errorf("normalizeAliases(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}

// Every short form a command accepts is declared, so help prints it. `-y` worked on
// prepare and uninstall for a long time while the page named only `--yes` — an
// undocumented flag, which is the one thing the Flags list exists to prevent.
func TestShortFormsAreDeclared(t *testing.T) {
	for _, c := range Commands {
		for _, f := range c.Flags {
			if f.Alias == "" {
				continue
			}
			if len(f.Alias) != 1 {
				t.Errorf("%s: --%s has alias %q; a short form is one letter", c.Name, f.Name, f.Alias)
			}
			var page strings.Builder
			commandHelp(&page, c)
			if !strings.Contains(page.String(), "-"+f.Alias+", --"+f.Name) {
				t.Errorf("%s: -%s is accepted but the help page does not show it", c.Name, f.Alias)
			}
		}
	}
}

// parserFiles are the only files allowed to compare an argument against a literal
// flag. They are the flag machinery itself; everything else must go through it.
var parserFiles = map[string]bool{
	"auth.go":      true, // ParseArgs
	"provision.go": true, // hasFlag
	"dispatch.go":  true, // parseInvocation (--json) and unknownFlag
}

// handRolled matches a comparison of an argument against a literal that looks like a
// flag — `args[i] == "--tail"`, `case "-n", "--tail":`, and so on.
var handRolled = regexp.MustCompile(`(?:==\s*"-|case\s+"-)`)

// No command parses flags by hand. This is a text scan rather than a behavioural
// test, and it earns its place anyway: the bug it guards against is invisible from
// the outside — the flag is declared, the gate admits it, help documents it, and the
// command simply does nothing with it. There is no failing assertion to write at the
// boundary, because from the boundary everything looks fine.
//
// If this fires on something legitimate, the fix is to use core.ParseArgs, not to add
// a file to parserFiles. The list is short on purpose.
func TestNoCommandParsesFlagsByHand(t *testing.T) {
	root := ".."
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		name := filepath.Base(path)
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			return nil
		}
		if parserFiles[name] {
			return nil
		}
		src, err := os.ReadFile(path) // #nosec G304 -- walking our own source tree in a test
		if err != nil {
			return err
		}
		for i, line := range strings.Split(string(src), "\n") {
			code := line
			if c := strings.Index(code, "//"); c >= 0 {
				code = code[:c] // a comment may talk about "--tail" freely
			}
			if handRolled.MatchString(code) {
				t.Errorf("%s:%d parses a flag by hand — use core.ParseArgs:\n\t%s",
					path, i+1, strings.TrimSpace(line))
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
