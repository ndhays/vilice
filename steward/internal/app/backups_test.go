package app

import (
	"path/filepath"
	"testing"
)

// The backup fact keeps each target's last success and last failure apart, so a reader
// can say both "backed up an hour ago" and "the last attempt failed".
func TestNoteBackupKeepsSuccessAndFailureApart(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_RECORD", filepath.Join(dir, "record.log")) // stateDir derives from this

	noteBackup("web", nil, "backed up")
	noteBackup("web", errBackup, "repo unreachable")

	run := loadBackups()["web"]
	if run.LastOK == "" || run.LastFailed == "" {
		t.Fatalf("want both times kept, got %+v", run)
	}
	if run.Error != "repo unreachable" {
		t.Errorf("Error = %q, want the failure's reason", run.Error)
	}

	// A later success clears the reason but keeps when it last failed.
	noteBackup("web", nil, "backed up")
	run = loadBackups()["web"]
	if run.Error != "" || run.LastFailed == "" {
		t.Errorf("after a success: %+v", run)
	}

	// Targets are independent, and the record snapshot has its own key.
	noteBackup(machineTarget, nil, "ok")
	if _, ok := loadBackups()[machineTarget]; !ok {
		t.Error("machine target not noted")
	}
}

// Status reports an unconfigured box as configured:false — a fact, not silence.
func TestCollectBackupsSaysWhenNothingIsConfigured(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_RECORD", filepath.Join(dir, "record.log"))
	t.Setenv("STEWARD_BACKUP_CONFIG", filepath.Join(dir, "backup.json"))
	got := collectBackups()
	if got["configured"] != false {
		t.Errorf("configured = %v, want false", got["configured"])
	}
}
