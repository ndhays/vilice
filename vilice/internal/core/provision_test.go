package core

import (
	"strings"
	"testing"
)

// The timer names itself, so its runs are never recorded under `operator` — the name
// a person at the box's shell gets.
func TestSnapshotTimerNamesItsActor(t *testing.T) {
	unit := snapshotService("/usr/local/bin/vilice")
	if !strings.Contains(unit, "Environment=VILICE_ACTOR="+SnapshotActor+"\n") {
		t.Fatalf("snapshot service does not name its actor:\n%s", unit)
	}
	if SnapshotActor == "operator" {
		t.Fatal("the timer's actor must differ from the local default")
	}
}
