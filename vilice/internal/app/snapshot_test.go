package app

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSnapshotAppends(t *testing.T) {
	path := filepath.Join(t.TempDir(), "status.jsonl")
	t.Setenv("VILICE_STATUS", path)

	if res := snapshotCmd(nil); res.Code != "ok" {
		t.Fatalf("snapshot: %+v", res)
	}
	if res := snapshotCmd(nil); res.Code != "ok" {
		t.Fatalf("second snapshot: %+v", res)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) != 2 {
		t.Fatalf("expected 2 samples, got %d", len(lines))
	}
	var pt snapshotPoint
	if err := json.Unmarshal([]byte(lines[0]), &pt); err != nil {
		t.Fatalf("sample is not valid JSON: %v", err)
	}
	if pt.Time == "" {
		t.Error("snapshot has no timestamp")
	}
}
