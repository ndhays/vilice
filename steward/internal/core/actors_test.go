package core

import (
	"strings"
	"testing"
)

// A real ed25519 public key, so the fingerprint is a real one.
const (
	edKey  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqE5ebQnxQemZTMc32SzDIiW4ciHUXRCeYzXnj9Mw3e"
	edFpr  = "SHA256:XUzzJ//1wmsYSU9cXimouTjlcOpATFfXb111dy7dQ8Y"
	pinned = `command="/usr/local/bin/steward _exec --client %s --scope %s",restrict ` + edKey
)

func grantLine(client, scope string) string {
	return strings.Replace(strings.Replace(pinned, "%s", client, 1), "%s", scope, 1)
}

func TestParseLedgerReadsAGrant(t *testing.T) {
	got := parseLedger(grantLine("console", "operate") + " console@laptop\n")
	if len(got) != 1 {
		t.Fatalf("got %d actors, want 1", len(got))
	}
	a := got[0]
	if !a.Pinned {
		t.Error("a line steward wrote should be pinned")
	}
	if a.Client != "console" || a.Scope != "operate" {
		t.Errorf("client/scope = %q/%q, want console/operate", a.Client, a.Scope)
	}
	if a.KeyType != "ssh-ed25519" || a.Fingerprint != edFpr {
		t.Errorf("key = %q %q, want ssh-ed25519 %s", a.KeyType, a.Fingerprint, edFpr)
	}
	if a.Comment != "console@laptop" {
		t.Errorf("comment = %q", a.Comment)
	}
	// The key itself is not reproduced — a fingerprint identifies it without
	// handing a reader the material to paste somewhere.
	if strings.Contains(a.Raw, "AAAAC3") {
		t.Error("a pinned grant should not carry the raw key")
	}
}

// The point of the verb. A key added by hand — no forced command — is a way onto the
// box that never passes the gate, and this is the only place it can become visible.
func TestAnUnpinnedKeyIsReportedAsSuch(t *testing.T) {
	got := parseLedger(grantLine("console", "operate") + "\n" + edKey + " sneaky@elsewhere\n")
	if len(got) != 2 {
		t.Fatalf("got %d actors, want 2", len(got))
	}
	// Unpinned sorts first: it is the one that needs attention.
	if got[0].Pinned {
		t.Fatal("the unpinned line should lead")
	}
	if got[0].Fingerprint != edFpr {
		t.Errorf("fingerprint = %q, want %s", got[0].Fingerprint, edFpr)
	}
	if got[0].Raw == "" {
		t.Error("an unpinned line should carry its raw text — there is nothing else to show")
	}

	out := renderActors(got, 1)
	if !strings.Contains(out, "NOT Steward grants") {
		t.Errorf("the human output must say so plainly:\n%s", out)
	}
	if !strings.Contains(out, "without passing the gate") {
		t.Errorf("the human output must say what it means:\n%s", out)
	}
}

// A forced command that is not `_exec` with a client and a scope is not a grant this
// binary would write, whatever else it is — treat it as unpinned rather than parse it
// into something reassuring.
func TestAForeignForcedCommandIsNotAGrant(t *testing.T) {
	for _, line := range []string{
		`command="/bin/bash",restrict ` + edKey,
		`command="/usr/local/bin/steward status",restrict ` + edKey,
		`command="/usr/local/bin/steward _exec --scope operate",restrict ` + edKey, // no client
		`command="/usr/local/bin/steward _exec --client ci",restrict ` + edKey,     // no scope
	} {
		got := parseLedger(line + "\n")
		if len(got) != 1 {
			t.Fatalf("got %d actors for %q", len(got), line)
		}
		if got[0].Pinned {
			t.Errorf("treated a foreign forced command as a grant: %q", line)
		}
	}
}

func TestLedgerSkipsBlanksAndComments(t *testing.T) {
	got := parseLedger("# a note\n\n   \n" + grantLine("ci", "observe") + "\n")
	if len(got) != 1 || got[0].Client != "ci" {
		t.Errorf("got %+v, want one ci grant", got)
	}
}

// The fingerprint is the same string `ssh-keygen -lf` prints, so an operator can
// compare it against the key in their hand rather than trusting our copy of it.
func TestFingerprintMatchesOpenSSH(t *testing.T) {
	if got := fingerprint(edKey); got != edFpr {
		t.Errorf("fingerprint = %q, want %q", got, edFpr)
	}
	if got := fingerprint("not a key"); got != "" {
		t.Errorf("garbage should fingerprint as empty, got %q", got)
	}
}

// A ledger that is absent is not an error: a box nobody has been admitted to is a
// legitimate state, and it should read as such rather than as a failure.
func TestNoLedgerReadsAsNobody(t *testing.T) {
	t.Setenv(AuthorizedKeysEnv, t.TempDir()+"/authorized_keys")
	res := actorsCmd(nil)
	if res.Code != "ok" {
		t.Fatalf("code = %q, want ok", res.Code)
	}
	if !strings.Contains(res.Message, "nobody can reach this box") {
		t.Errorf("message = %q", res.Message)
	}
}

// actors is a read: it holds no privilege and writes nothing to the chain.
func TestActorsIsAnUnrecordedRead(t *testing.T) {
	cmd, ok := Lookup("actors")
	if !ok {
		t.Fatal("actors is not registered")
	}
	if cmd.Scope != ScopeObserve {
		t.Errorf("scope = %q, want observe", cmd.Scope)
	}
	if recordable(cmd, nil) {
		t.Error("a read must not be recorded")
	}
	if !cmd.SkipBinaryCheck {
		t.Error("who may act on this box must be readable even when the binary is not the recorded one")
	}
}
