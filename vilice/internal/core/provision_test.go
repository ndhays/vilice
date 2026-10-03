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

// The ranges are written for the account that exists. 0.4.0 shipped them for `vilice`
// while the account is `_vilice`; nothing tested the name, so nothing noticed.
func TestSubidRangesAreForTheAccount(t *testing.T) {
	script := subidScript(ViliceUser)
	for _, want := range []string{
		"grep -q '^" + ViliceUser + ":' \"$f\"",
		"echo '" + ViliceUser + ":100000:65536' >> \"$f\"",
		"/etc/subuid", "/etc/subgid",
	} {
		if !strings.Contains(script, want) {
			t.Errorf("subid script is missing %q:\n%s", want, script)
		}
	}
	// The stray 0.4.0 entry is removed only when no real `vilice` user could own it.
	if !strings.Contains(script, "id vilice >/dev/null 2>&1 || sed -i '/^vilice:100000:65536$/d'") {
		t.Errorf("the stray `vilice` range should be taken back out:\n%s", script)
	}
}

// prepare makes the ledger's directory, so a box nobody has been authorized on yet
// passes doctor. sshd wants it owned by the account and closed to everyone else.
func TestPrepareMakesTheLedgerDirectory(t *testing.T) {
	script := ledgerDirScript(ViliceUser)
	if !strings.Contains(script, "install -d -m 0700 -o "+ViliceUser+" -g "+ViliceUser+" \"$home/.ssh\"") {
		t.Errorf("ledger dir script does not make ~/.ssh 0700 for the account:\n%s", script)
	}
	if !strings.Contains(script, "getent passwd "+ViliceUser) {
		t.Errorf("the home directory should come from the passwd database:\n%s", script)
	}
}
