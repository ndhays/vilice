package core

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// useManifest points the manifest at a temp file for the duration of a test. The
// real path is deliberately not settable from a flag or the environment, so this is
// the only way in — and it is in-package, which is the point.
func useManifest(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "packs.manifest")
	if body != "" {
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	old := packManifestPath
	packManifestPath = path
	t.Cleanup(func() { packManifestPath = old })
	return path
}

// runFake dispatches one of the fake pack's verbs and reports the exit code.
func runFake(t *testing.T, verb string) int {
	t.Helper()
	useTempRecord(t)
	cmd, ok := Lookup(verb)
	if !ok {
		t.Fatalf("no verb %q", verb)
	}
	if cmd.Pack == "" {
		t.Fatalf("%q is a core verb; this test needs a packed one", verb)
	}
	return Dispatch(cmd, nil, "ci", true)
}

// The happy path: a pack listed at this binary's digest runs.
func TestPackedVerbRunsWhenTheManifestAuthorizesIt(t *testing.T) {
	digest, err := SelfDigest()
	if err != nil {
		t.Fatal(err)
	}
	useManifest(t, "steward-fake "+digest+"\n")
	if code := runFake(t, "status"); code != 0 {
		t.Errorf("exit %d, want 0 — an authorized pack should run", code)
	}
}

// The proof that the boundary is real rather than decorative: flip one byte of the
// authorized digest and every verb the pack contributes stops, while the core's own
// verbs — the ones an operator needs to see why — keep working.
func TestATamperedDigestStopsThePackButNotTheCore(t *testing.T) {
	digest, err := SelfDigest()
	if err != nil {
		t.Fatal(err)
	}
	tampered := digest[:len(digest)-1] + "0"
	if tampered == digest {
		tampered = digest[:len(digest)-1] + "1"
	}
	useManifest(t, "steward-fake "+tampered+"\n")

	for _, verb := range []string{"status", "deploy", "logs"} {
		if code := runFake(t, verb); code != 1 {
			t.Errorf("%s: exit %d, want 1 — the manifest and the binary disagree", verb, code)
		}
	}

	// The core keeps working. If a digest mismatch took `verify` and `record` down
	// with it, the operator would be locked out of the very evidence that explains
	// the refusal.
	useTempRecord(t)
	for _, verb := range []string{"verify", "record"} {
		cmd, _ := Lookup(verb)
		if cmd.Pack != "" {
			t.Fatalf("%s should be a core verb", verb)
		}
		if code := Dispatch(cmd, nil, "ci", true); code != 0 {
			t.Errorf("%s: exit %d, want 0 — core verbs must survive a pack mismatch", verb, code)
		}
	}
}

// Presence is not permission, and neither is absence a default-allow.
func TestAnUnlistedOrMissingManifestRefuses(t *testing.T) {
	t.Run("pack not listed", func(t *testing.T) {
		digest, _ := SelfDigest()
		useManifest(t, "steward-somethingelse "+digest+"\n")
		if code := runFake(t, "status"); code != 1 {
			t.Errorf("exit %d, want 1 — an unlisted pack must not run", code)
		}
	})
	t.Run("no manifest at all", func(t *testing.T) {
		useManifest(t, "") // path exists in a temp dir; the file does not
		if code := runFake(t, "status"); code != 1 {
			t.Errorf("exit %d, want 1 — a box that never said which code may run says no", code)
		}
	})
}

// A refusal is itself an act worth knowing about: unlike a typo'd flag, "the binary
// and the manifest disagree" is not the caller's mistake.
func TestARefusalIsRecorded(t *testing.T) {
	useManifest(t, "steward-fake sha256:deadbeef\n")
	path := useTempRecord(t)
	cmd, _ := Lookup("status")
	if code := Dispatch(cmd, nil, "ci", true); code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), "pack-unauthorized") {
		t.Errorf("the refusal was not recorded:\n%s", b)
	}
}

func TestReadManifestRejectsMalformedLines(t *testing.T) {
	for _, body := range []string{
		"steward-app\n",                  // no digest
		"steward-app sha256:abc extra\n", // too many fields
		"steward-app abc123\n",           // digest not sha256-prefixed
		"steward-app md5:abc\n",          // wrong algorithm
	} {
		path := useManifest(t, body)
		if _, err := readManifest(path); err == nil {
			t.Errorf("accepted a malformed manifest line: %q", body)
		}
	}
}

func TestManifestIgnoresBlanksAndComments(t *testing.T) {
	path := useManifest(t, "# a comment\n\n  \nsteward-app sha256:abc\n")
	entries, err := readManifest(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Pack != "steward-app" || entries[0].Digest != "sha256:abc" {
		t.Errorf("got %+v, want one steward-app entry", entries)
	}
}

// The record schema has to grow additively or it invalidates history. `verify`
// recomputes every hash, so if adding pack/digest had widened the payload for *all*
// entries, every chain already on a box would report a break at entry 1 — the record
// accusing itself of tampering because the software changed.
//
// These hashes are pinned. A change to either payload shape breaks this test loudly,
// which is the only warning anyone gets before shipping a version that cannot read
// its own past.
func TestRecordHashesArePinned(t *testing.T) {
	packless := Entry{Seq: 1, Time: "2026-01-01T00:00:00Z", Actor: "operator",
		Scope: "root", Action: "prepare"}
	const wantPackless = "c886828c93b3c99c2d3be4ce9d7824d2431a03c96ce35dd512f64509bc100048"
	if got := packless.computeHash(); got != wantPackless {
		t.Errorf("a pack-less entry no longer hashes as it did — every chain on every\n"+
			"box would fail verify.\ngot  %s\nwant %s", got, wantPackless)
	}

	packed := Entry{Seq: 2, Time: "2026-01-01T00:00:01Z", Actor: "ci", Scope: "operate",
		Action: "deploy", Args: []string{"web"}, Pack: "steward-app",
		Digest: "sha256:abc", PrevHash: "x"}
	const wantPacked = "a9a7cd585035c58e670226a437b97e31dc3d1d44fdc6238b0450eb2a214b7f60"
	if got := packed.computeHash(); got != wantPacked {
		t.Errorf("the packed entry shape changed.\ngot  %s\nwant %s", got, wantPacked)
	}

	// And the two shapes are genuinely different: the pack and digest are covered by
	// the hash, not decoration sitting outside it. Stripping them from an entry has
	// to change the hash, or the record could not attest which code ran.
	stripped := packed
	stripped.Pack, stripped.Digest = "", ""
	if stripped.computeHash() == packed.computeHash() {
		t.Error("pack and digest are not covered by the hash — they could be edited freely")
	}
}

// A chain that mixes entries from before and after packs existed verifies end to end.
func TestAMixedChainVerifies(t *testing.T) {
	useTempRecord(t)
	if err := Record("operator", "root", "prepare", nil); err != nil {
		t.Fatal(err)
	}
	if err := RecordAct("ci", "operate", "deploy", []string{"web"}, "steward-app", "sha256:abc"); err != nil {
		t.Fatal(err)
	}
	if err := Record("operator", "grant", "authorize", []string{"ci"}); err != nil {
		t.Fatal(err)
	}
	if res := verifyCmd(nil); res.Code != "ok" {
		t.Errorf("verify = %q (%s), want ok", res.Code, res.Message)
	}
}
