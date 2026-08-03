package core

import (
	"strings"
	"testing"
)

const (
	digestA = "sha256:aaa"
	digestB = "sha256:bbb"
)

func stateOf(t *testing.T, states []PackState, name string) PackState {
	t.Helper()
	for _, s := range states {
		if s.Name == name {
			return s
		}
	}
	t.Fatalf("no state reported for %q (got %+v)", name, states)
	return PackState{}
}

// The happy case: authorized at this binary's digest, and carried.
func TestPacksReportsAnActivePack(t *testing.T) {
	got := packStates(
		[]manifestEntry{{Pack: "steward-app", Digest: digestA}},
		[]string{"steward-app"}, digestA, true)
	if s := stateOf(t, got, "steward-app"); s.State != packActive {
		t.Errorf("state = %q, want %q", s.State, packActive)
	}
}

// Authorized at a digest this binary is not. Nothing runs, and the reason is not
// obvious from the refusal alone — an upgrade that skipped `prepare` looks exactly
// like a tampered binary until you can see both digests side by side.
func TestPacksReportsAStaleAuthorization(t *testing.T) {
	got := packStates(
		[]manifestEntry{{Pack: "steward-app", Digest: digestB}},
		[]string{"steward-app"}, digestA, true)
	s := stateOf(t, got, "steward-app")
	if s.State != packStale {
		t.Errorf("state = %q, want %q", s.State, packStale)
	}
	if !strings.Contains(s.Note, "prepare") {
		t.Errorf("the note should say how to fix it; got %q", s.Note)
	}
}

// Authorized, but this binary does not carry it — a manifest written by a build that
// had a pack this one doesn't.
func TestPacksReportsAMissingPack(t *testing.T) {
	got := packStates(
		[]manifestEntry{{Pack: "steward-backup", Digest: digestA}},
		[]string{"steward-app"}, digestA, true)
	if s := stateOf(t, got, "steward-backup"); s.State != packMissing {
		t.Errorf("state = %q, want %q", s.State, packMissing)
	}
}

// Carried but unauthorized: the verbs exist in the binary and are refused at the
// gate. Without this read, that code is invisible — it is not in the manifest, so
// nothing lists it, and it never runs, so nothing fails.
func TestPacksReportsCarriedButUnauthorized(t *testing.T) {
	got := packStates(nil, []string{"steward-app"}, digestA, true)
	s := stateOf(t, got, "steward-app")
	if s.State != packUnauthorized {
		t.Errorf("state = %q, want %q", s.State, packUnauthorized)
	}
	if !strings.Contains(s.Note, "refused") {
		t.Errorf("the note should say the verbs are refused; got %q", s.Note)
	}
}

// Whatever is wrong sorts first — that is what a reader opened this for.
func TestPacksPutsProblemsFirst(t *testing.T) {
	got := packStates(
		[]manifestEntry{{Pack: "steward-app", Digest: digestA}, {Pack: "steward-zzz", Digest: digestB}},
		[]string{"steward-app"}, digestA, true)
	if got[0].State == packActive {
		t.Errorf("an active pack led the list; problems should:\n%+v", got)
	}
}

// A box with no manifest is a legitimate state — it is every box between `harden`
// and `prepare` — and must read as a fact, not a failure. Whatever the binary
// carries reads as unauthorized, which is the true statement: nothing may run.
func TestPacksWithNoManifestReadsAsNothingAuthorized(t *testing.T) {
	useManifest(t, "")
	res := packsCmd(nil)
	if res.Code != "ok" {
		t.Fatalf("code = %q, want ok — a fresh box is not an error", res.Code)
	}
	if !strings.Contains(res.Message, packUnauthorized) {
		t.Errorf("a carried pack should read as unauthorized; got:\n%s", res.Message)
	}
}

// And a binary carrying no packs at all, against no manifest, says so plainly
// rather than rendering an empty table.
func TestPacksWithNothingAtAllSaysCoreOnly(t *testing.T) {
	if got := renderPacks(packStates(nil, nil, digestA, true), "/etc/steward/packs.manifest"); !strings.Contains(got, "core and nothing else") {
		t.Errorf("got %q", got)
	}
}

// The verb itself: a core read, holding no privilege and writing nothing.
func TestPacksIsAnUnrecordedCoreRead(t *testing.T) {
	cmd, ok := Lookup("packs")
	if !ok {
		t.Fatal("packs is not registered")
	}
	if cmd.Scope != ScopeObserve {
		t.Errorf("scope = %q, want observe", cmd.Scope)
	}
	if recordable(cmd, nil) {
		t.Error("a read must not be recorded")
	}
	if cmd.Pack != "" {
		t.Error("the manifest is the core's; packs must not itself be a pack verb")
	}
}
