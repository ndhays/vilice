package core

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// Invariant 2 under concurrency. Steward Console driving a box while an operator types is
// the ordinary case, and the record is append-only — a chain broken by a race cannot be
// repaired without root, so this is the one that must never regress.
func TestRecordSurvivesConcurrentWriters(t *testing.T) {
	path := useTempRecord(t)
	const writers = 25

	var wg sync.WaitGroup
	errs := make(chan error, writers)
	for i := 0; i < writers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := Record("console", "operate", "deploy", []string{"web"}); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent record failed: %v", err)
	}

	if err := verifyChain(path); err != nil {
		t.Fatalf("chain broken by concurrent writers: %v", err)
	}
	// Every writer must have landed, each with its own contiguous seq.
	entries, err := readEntries(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != writers {
		t.Fatalf("want %d entries, got %d — a write was lost", writers, len(entries))
	}
}

// A torn final line (crash or full disk mid-append) must stop every state-changing
// command — chaining onto an entry we can't read would fake the history — and the
// refusal must carry the way out, not just the parse error.
func TestTornRecordRefusesAndSaysHowToRepair(t *testing.T) {
	path := useTempRecord(t)
	if err := Record("operator", "root", "prepare", nil); err != nil {
		t.Fatal(err)
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(`{"seq":2,"time":"2026-0`); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	err = Record("console", "operate", "deploy", []string{"web"})
	if err == nil {
		t.Fatal("a torn record must refuse the next action, not chain onto it")
	}
	for _, want := range []string{"chattr -a", "steward verify", path} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal should point at the repair; missing %q in:\n%s", want, err)
		}
	}
}

// useTempRecord points the record at a throwaway file for the duration of a test.
func useTempRecord(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "record.log")
	t.Setenv("STEWARD_RECORD", path)
	return path
}

func TestRecordGenesis(t *testing.T) {
	path := useTempRecord(t)
	if err := Record("operator", "root", "prepare", nil); err != nil {
		t.Fatalf("record: %v", err)
	}
	last, found, err := lastEntry(path)
	if err != nil || !found {
		t.Fatalf("lastEntry: found=%v err=%v", found, err)
	}
	if last.Seq != 1 {
		t.Errorf("first entry seq = %d, want 1", last.Seq)
	}
	if last.PrevHash != "" {
		t.Errorf("genesis prev_hash = %q, want empty", last.PrevHash)
	}
	if last.Hash == "" {
		t.Error("genesis hash is empty")
	}
}

func TestRecordChains(t *testing.T) {
	path := useTempRecord(t)
	if err := Record("operator", "root", "harden", nil); err != nil {
		t.Fatal(err)
	}
	if err := Record("console", "operate", "deploy", []string{"app1", "--image", "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000"}); err != nil {
		t.Fatal(err)
	}
	if err := Record("operator", "root", "authorize", []string{"--client", "ci"}); err != nil {
		t.Fatal(err)
	}

	last, _, err := lastEntry(path)
	if err != nil {
		t.Fatal(err)
	}
	if last.Seq != 3 {
		t.Errorf("seq = %d, want 3", last.Seq)
	}
	if last.Actor != "operator" || last.Action != "authorize" {
		t.Errorf("last entry = %+v", last)
	}
	if err := verifyChain(path); err != nil {
		t.Errorf("verifyChain on a clean record: %v", err)
	}
}

// A no-arg command reaches record() with an empty, non-nil slice (dispatch passes
// filtered[1:]). `omitempty` drops it on disk and it reloads as nil on verify — so an
// empty arg list and a nil one must hash identically, or the very first entries on a
// real box (prepare, harden, apply-updates) break their own chain.
func TestVerifyChainEmptyArgsHashStable(t *testing.T) {
	path := useTempRecord(t)
	if err := Record("operator", "root", "prepare", []string{}); err != nil {
		t.Fatal(err)
	}
	if err := Record("operator", "operate", "apply-updates", []string{}); err != nil {
		t.Fatal(err)
	}
	if err := verifyChain(path); err != nil {
		t.Fatalf("no-arg (empty slice) record must verify clean: %v", err)
	}
}

func TestVerifyChainDetectsTamper(t *testing.T) {
	path := useTempRecord(t)
	for _, a := range []string{"prepare", "deploy", "restart"} {
		if err := Record("operator", "operate", a, nil); err != nil {
			t.Fatal(err)
		}
	}
	if err := verifyChain(path); err != nil {
		t.Fatalf("baseline should verify: %v", err)
	}

	// Edit the middle entry's action in place. Its stored hash no longer matches
	// its contents, so the chain must report a break.
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	tampered := []byte(replaceFirst(string(data), `"action":"deploy"`, `"action":"remove"`))
	if string(tampered) == string(data) {
		t.Fatal("test setup: expected to find the deploy entry to tamper")
	}
	if err := os.WriteFile(path, tampered, 0o644); err != nil {
		t.Fatal(err)
	}

	if err := verifyChain(path); err == nil {
		t.Error("verifyChain accepted a tampered record")
	}
}

func TestVerifyChainDetectsDeletion(t *testing.T) {
	path := useTempRecord(t)
	for _, a := range []string{"prepare", "deploy", "restart"} {
		if err := Record("operator", "operate", a, nil); err != nil {
			t.Fatal(err)
		}
	}
	// Drop the middle line: seq jumps 1 -> 3 and the prev-hash link breaks.
	data, _ := os.ReadFile(path)
	lines := splitLines(string(data))
	if len(lines) < 3 {
		t.Fatalf("expected 3 entries, got %d", len(lines))
	}
	kept := lines[0] + "\n" + lines[2] + "\n"
	if err := os.WriteFile(path, []byte(kept), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := verifyChain(path); err == nil {
		t.Error("verifyChain accepted a record with a deleted entry")
	}
}

// TestVerifyCmd covers the observe-scope command wrapper: an empty record is
// intact-with-zero, a real chain reports its length, and a tampered one is broken.
func TestVerifyCmd(t *testing.T) {
	path := useTempRecord(t)

	if res := verifyCmd(nil); res.Code != "ok" {
		t.Fatalf("empty record: code = %q (%s), want ok", res.Code, res.Message)
	}

	for _, a := range []string{"prepare", "deploy", "restart"} {
		if err := Record("operator", "operate", a, nil); err != nil {
			t.Fatal(err)
		}
	}
	res := verifyCmd(nil)
	if res.Code != "ok" {
		t.Fatalf("clean chain: code = %q (%s), want ok", res.Code, res.Message)
	}
	if data, ok := res.Data.(map[string]any); !ok || data["entries"] != 3 {
		t.Errorf("Data = %v, want entries=3", res.Data)
	}

	if err := os.WriteFile(path, []byte(`{"seq":1,"action":"x","hash":"deadbeef"}`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if res := verifyCmd(nil); res.Code != "record_broken" {
		t.Errorf("tampered record: code = %q, want record_broken", res.Code)
	}
}

// replaceFirst replaces the first occurrence of old with new.
func replaceFirst(s, old, new string) string {
	i := indexOf(s, old)
	if i < 0 {
		return s
	}
	return s[:i] + new + s[i+len(old):]
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

func splitLines(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			if i > start {
				out = append(out, s[start:i])
			}
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}
