package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// useBinaryDigest points the digest record at a temp file for the duration of a
// test. The real path is deliberately not settable from a flag or the environment,
// so this is the only way in — and it is in-package, which is the point.
func useBinaryDigest(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "binary.digest")
	if body != "" {
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	old := binaryDigestPath
	binaryDigestPath = path
	t.Cleanup(func() { binaryDigestPath = old })
	return path
}

// runChecked dispatches a verb that is subject to the binary check and reports the
// exit code.
func runChecked(t *testing.T, verb string) int {
	t.Helper()
	useTempRecord(t)
	cmd, ok := Lookup(verb)
	if !ok {
		t.Fatalf("no verb %q", verb)
	}
	if cmd.SkipBinaryCheck {
		t.Fatalf("%q skips the binary check; this test needs a checked verb", verb)
	}
	return Dispatch(cmd, nil, "ci", true)
}

// The happy path: the binary this box recorded is the binary that runs.
func TestAVerbRunsWhenTheBinaryIsTheRecordedOne(t *testing.T) {
	digest, err := SelfDigest()
	if err != nil {
		t.Fatal(err)
	}
	useBinaryDigest(t, digest+"\n")
	if code := runChecked(t, "status"); code != 0 {
		t.Errorf("exit %d, want 0 — the authorized binary should run", code)
	}
}

// The proof that the boundary is real rather than decorative: flip one byte of the
// recorded digest and every verb that acts stops, while the ones an operator needs
// to see why keep working.
func TestATamperedDigestStopsTheVerbsButNotTheRepairPath(t *testing.T) {
	digest, err := SelfDigest()
	if err != nil {
		t.Fatal(err)
	}
	tampered := digest[:len(digest)-1] + "0"
	if tampered == digest {
		tampered = digest[:len(digest)-1] + "1"
	}
	useBinaryDigest(t, tampered+"\n")

	for _, verb := range []string{"status", "deploy", "logs"} {
		if code := runChecked(t, verb); code != 1 {
			t.Errorf("%s: exit %d, want 1 — the recorded digest and the binary disagree", verb, code)
		}
	}

	// The repair path keeps working. If a digest mismatch took `verify` and `record`
	// down with it, the operator would be locked out of the very evidence that
	// explains the refusal.
	useTempRecord(t)
	for _, verb := range []string{"verify", "record"} {
		cmd, _ := Lookup(verb)
		if !cmd.SkipBinaryCheck {
			t.Fatalf("%s must survive a digest mismatch", verb)
		}
		if code := Dispatch(cmd, nil, "ci", true); code != 0 {
			t.Errorf("%s: exit %d, want 0 — the repair path must survive a mismatch", verb, code)
		}
	}
}

// The verbs that stay open on a box whose binary was replaced, named here so the
// list is a decision rather than an accident. Anything not on it is checked, and a
// verb added without a thought about this is checked by default.
func TestOnlyTheRepairPathSkipsTheCheck(t *testing.T) {
	want := map[string]bool{
		"harden": true, "prepare": true, "uninstall": true, // the ceiling; prepare is the repair
		"authorize": true, "revoke": true, // withdrawing a key must not need a trusted box
		"verify": true, "record": true, "actors": true, // the evidence
	}
	for _, c := range Commands {
		if c.SkipBinaryCheck != want[c.Name] {
			t.Errorf("%s: SkipBinaryCheck = %v, want %v", c.Name, c.SkipBinaryCheck, want[c.Name])
		}
	}
}

// Absence is not a default-allow. A box that never said which binary may run says no.
func TestAMissingDigestRecordRefuses(t *testing.T) {
	useBinaryDigest(t, "") // path exists in a temp dir; the file does not
	if code := runChecked(t, "status"); code != 1 {
		t.Errorf("exit %d, want 1 — a box that never authorized a binary says no", code)
	}
}

// A refusal is itself an act worth knowing about: unlike a typo'd flag, "this is not
// the binary this box authorized" is not the caller's mistake.
func TestARefusalIsRecorded(t *testing.T) {
	useBinaryDigest(t, "sha256:deadbeef\n")
	path := useTempRecord(t)
	cmd, _ := Lookup("status")
	if code := Dispatch(cmd, nil, "ci", true); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), "binary-unrecognized") {
		t.Errorf("the refusal was not recorded:\n%s", b)
	}
}

func TestReadBinaryDigestRejectsMalformedFiles(t *testing.T) {
	for _, body := range []string{
		"abc123\n",                 // not sha256-prefixed
		"md5:abc\n",                // wrong algorithm
		"sha256:abc extra\n",       // more than a bare digest
		"sha256:abc\nsha256:def\n", // a box authorizes one binary
		"# only a comment\n",       // nothing authorized
	} {
		path := useBinaryDigest(t, body)
		if _, err := readBinaryDigest(path); err == nil {
			t.Errorf("accepted a malformed digest record: %q", body)
		}
	}
}

func TestBinaryDigestIgnoresBlanksAndComments(t *testing.T) {
	path := useBinaryDigest(t, "# a comment\n\n  \nsha256:abc\n")
	digest, err := readBinaryDigest(path)
	if err != nil {
		t.Fatal(err)
	}
	if digest != "sha256:abc" {
		t.Errorf("got %q, want sha256:abc", digest)
	}
}

// What `prepare` writes is what the check reads back — one round trip, so the two
// halves cannot drift into disagreeing about the format.
func TestWhatPrepareWritesIsWhatTheCheckReads(t *testing.T) {
	useBinaryDigest(t, "")
	written, err := writeBinaryDigest()
	if err != nil {
		t.Fatal(err)
	}
	got, err := checkBinaryDigest()
	if err != nil {
		t.Fatalf("the file prepare just wrote did not pass the check: %v", err)
	}
	if got != written {
		t.Errorf("check returned %q, want %q", got, written)
	}
}

// The record schema has to grow additively or it invalidates history. `verify`
// recomputes every hash, so if adding the digest had widened the payload for *all*
// entries, every chain already on a box would report a break at entry 1 — the record
// accusing itself of tampering because the software changed.
//
// The `pack` field is retired but still hashed: entries written by earlier versions
// carry it, and dropping it from the payload would accuse every one of them.
//
// These hashes are pinned. A change to either payload shape breaks this test loudly,
// which is the only warning anyone gets before shipping a version that cannot read
// its own past.
func TestRecordHashesArePinned(t *testing.T) {
	bare := Entry{Seq: 1, Time: "2026-01-01T00:00:00Z", Actor: "operator",
		Scope: "root", Action: "prepare"}
	const wantBare = "c886828c93b3c99c2d3be4ce9d7824d2431a03c96ce35dd512f64509bc100048"
	if got := bare.computeHash(); got != wantBare {
		t.Errorf("an entry naming no binary no longer hashes as it did — every chain on\n"+
			"every box would fail verify.\ngot  %s\nwant %s", got, wantBare)
	}

	// A historical entry, from when the pack layer existed. Boxes still hold these.
	packed := Entry{Seq: 2, Time: "2026-01-01T00:00:01Z", Actor: "ci", Scope: "operate",
		Action: "deploy", Args: []string{"web"}, Pack: "steward-app",
		Digest: "sha256:abc", PrevHash: "x"}
	const wantPacked = "a9a7cd585035c58e670226a437b97e31dc3d1d44fdc6238b0450eb2a214b7f60"
	if got := packed.computeHash(); got != wantPacked {
		t.Errorf("the historical pack-bearing entry shape changed — boxes that hold one\n"+
			"would fail verify.\ngot  %s\nwant %s", got, wantPacked)
	}

	// And the digest is genuinely covered by the hash, not decoration sitting outside
	// it. Stripping it from an entry has to change the hash, or the record could not
	// attest which binary ran.
	stripped := packed
	stripped.Pack, stripped.Digest = "", ""
	if stripped.computeHash() == packed.computeHash() {
		t.Error("pack and digest are not covered by the hash — they could be edited freely")
	}
}

// A chain that mixes entry shapes — before the digest was recorded, the retired
// pack-bearing shape, and today's — verifies end to end.
func TestAMixedChainVerifies(t *testing.T) {
	useTempRecord(t)
	if err := Record("operator", "root", "prepare", nil); err != nil {
		t.Fatal(err)
	}
	if err := RecordAct("ci", "operate", "deploy", []string{"web"}, "sha256:abc"); err != nil {
		t.Fatal(err)
	}
	if err := Record("operator", "grant", "authorize", []string{"ci"}); err != nil {
		t.Fatal(err)
	}
	if res := verifyCmd(nil); res.Code != "ok" {
		t.Errorf("verify = %q (%s), want ok", res.Code, res.Message)
	}
}
