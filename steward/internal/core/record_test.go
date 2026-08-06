package core

import (
	"os"
	"path/filepath"
	"testing"
)

// recordCmd is the read side of the chain: it must dump every entry and report
// whether the chain is intact, so a reader (Steward Console) can show and verify it.
func TestRecordCmdDumpsEntriesAndIntegrity(t *testing.T) {
	path := filepath.Join(t.TempDir(), "record.log")
	t.Setenv("STEWARD_RECORD", path)

	data := func(r Result) map[string]any { return r.Data.(map[string]any) }

	// An absent record is an empty, intact record — not an error.
	res := recordCmd(nil)
	if res.Code != "ok" || data(res)["count"].(int) != 0 || data(res)["intact"].(bool) != true {
		t.Fatalf("empty record: got %+v", res.Data)
	}

	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(Record("operator", "root", "prepare", nil))
	must(Record("console", "operate", "deploy", []string{"app1", "--image", "x@sha256:abc0000000000000000000000000000000000000000000000000000000000000"}))
	must(Record("ci", "operate", "restart", []string{"app1"}))

	res = recordCmd(nil)
	entries := data(res)["entries"].([]Entry)
	if len(entries) != 3 || data(res)["intact"].(bool) != true {
		t.Fatalf("want 3 intact entries, got %d intact=%v", len(entries), data(res)["intact"])
	}
	if entries[0].Action != "prepare" || entries[2].Actor != "ci" {
		t.Fatalf("entries wrong/out of order: %+v", entries)
	}

	// Tamper: a line whose hash no longer matches its contents.
	must(os.WriteFile(path, []byte(`{"seq":1,"time":"2020-01-01T00:00:00Z","actor":"x","scope":"root","action":"prepare","prev_hash":"","hash":"bad"}`+"\n"), 0o644))
	res = recordCmd(nil)
	if data(res)["intact"].(bool) != false {
		t.Fatal("a tampered chain must report intact=false")
	}
}
