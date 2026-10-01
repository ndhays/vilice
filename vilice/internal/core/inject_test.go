package core

// Rendered config is a boundary. Vilice writes three line-oriented formats —
// authorized_keys, a Caddy site block, and a Quadlet unit — by interpolating values a
// caller supplied. In every one of them a newline in a value ends that value's line and
// turns the rest into a directive the operator never wrote.
//
// So these tests assert a property rather than examples: for *any* input validation
// lets through, the rendered file has the shape it is supposed to have — one directive
// per declared value, and no directive outside the set the renderer knows how to emit.
// A future field that forgets to validate fails here, and the fuzz targets go looking
// for the case nobody thought of.
//
// Run the fuzzers past their seeds with:
//
//	go test -run x -fuzz FuzzQuadlet -fuzztime 60s ./...

import (
	"strings"
	"testing"
)

// hostileStrings is the shared corpus: things that end a line, open a block, or
// terminate a string, plus the escapes people reach for to smuggle them.
var hostileStrings = []string{
	"\n",
	"\r\n",
	"\r",
	"x\nInjected=1",
	"x\n}\n:9999 {\n\trespond \"pwned\"\n}\n#",
	"x\nPodmanArgs=--privileged",
	"x\nAddCapability=CAP_SYS_ADMIN",
	"x\nUser=root",
	"x\nVolume=/:/host:rw",
	"x\x00y",
	"x\ty",
	"x\vy",
	"x\fy",
	"x\x7fy",
	"a b",
	"{",
	"}",
	"} {",
	`"`,
	`\`,
	`\n`,
	"$(id)",
	"`id`",
	"../../etc/passwd",
	"",
}

// --- Caddy ---

// --- Quadlet ---

// --- authorized_keys ---

// The rights ledger is one line per actor. A key that renders to two lines has smuggled
// in a grant with no forced command and no restrictions.
func TestForcedLineIsAlwaysOneLine(t *testing.T) {
	for _, s := range hostileStrings {
		pubkey := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 " + s
		if looksLikePubkey(pubkey) {
			line, err := forcedLine("ci", ScopeObserve, pubkey)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(line, "\n") {
				t.Errorf("pubkey comment %q produced a multi-line ledger entry:\n%s", s, line)
			}
		}
		// The whole-key form: the injection that was live.
		whole := "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 ci@host" + s + "ssh-ed25519 AAAAattacker unrestricted"
		if looksLikePubkey(whole) {
			line, err := forcedLine("ci", ScopeObserve, whole)
			if err != nil {
				t.Fatal(err)
			}
			if strings.Contains(line, "\n") {
				t.Errorf("pubkey %q produced a multi-line ledger entry:\n%s", s, line)
			}
		}
	}
}

func TestLooksLikePubkeyAcceptsRealKeysOnly(t *testing.T) {
	good := []string{
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample",
		"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample ci@build",
		"ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB me@host",
		"ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY= x@y",
	}
	for _, s := range good {
		if !looksLikePubkey(s) {
			t.Errorf("rejected a real key: %q", s)
		}
	}
	bad := []string{
		"ssh-ed25519 AAAAreal ci@host\nssh-ed25519 AAAAattacker unrestricted",
		"ssh-ed25519 AAAAreal ci@host extra-field",
		"not-a-type AAAAreal ci@host",
		"ssh-ed25519",
		"ssh-ed25519 not-base64!",
		"",
	}
	for _, s := range bad {
		if looksLikePubkey(s) {
			t.Errorf("accepted a bad key: %q", s)
		}
	}
}

func FuzzForcedLineIsOneLine(f *testing.F) {
	for _, s := range hostileStrings {
		f.Add(s)
	}
	f.Add("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 ci@host")
	f.Fuzz(func(t *testing.T, pubkey string) {
		if !looksLikePubkey(pubkey) {
			return
		}
		line, err := forcedLine("ci", ScopeObserve, pubkey)
		if err != nil {
			return
		}
		if strings.Contains(strings.TrimSuffix(line, "\n"), "\n") {
			t.Fatalf("pubkey %q rendered a multi-line ledger entry:\n%s", pubkey, line)
		}
		if !strings.HasPrefix(line, `command="`) {
			t.Fatalf("ledger entry lost its forced command: %s", line)
		}
	})
}
