package app

// The backup fact: when each target last backed up, and whether it worked.
//
// `backup` writes it, `status` reads it — the same split as hardening: the side that
// acts publishes what happened, and the observe read reports that and nothing more.
// `status` does not ask restic, because that would be a network call to the repo with
// the repo password in hand, from a zero-privilege read.
//
// One file, /var/lib/vilice/backups.json, keyed by target: an app's name, or
// "machine" for the record snapshot. Each keeps its last success and its last failure,
// so a reader can say "backed up 3 hours ago" and "the last attempt failed" at once.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// BackupRun is one target's history, as far as a reader needs it.
type BackupRun struct {
	LastOK     string `json:"last_ok,omitempty"`     // RFC 3339, the last snapshot that succeeded
	LastFailed string `json:"last_failed,omitempty"` // RFC 3339, the last attempt that failed
	Error      string `json:"error,omitempty"`       // why the last failure failed; cleared by a success
}

// machineTarget is the key for the record snapshot (`backup --machine`). Not a valid
// app name, so it cannot collide with one.
const machineTarget = "machine"

func backupsPath() string { return filepath.Join(stateDir(), "backups.json") }

func loadBackups() map[string]BackupRun {
	runs := map[string]BackupRun{}
	b, err := os.ReadFile(backupsPath()) // #nosec G304 -- vilice's own state file
	if err != nil {
		return runs
	}
	_ = json.Unmarshal(b, &runs) // an unreadable file reads as no history, not an error
	return runs
}

// noteBackup records one target's outcome. Best-effort: a backup that succeeded is not
// made to fail because its note could not be written.
func noteBackup(target string, err error, message string) {
	runs := loadBackups()
	run := runs[target]
	now := time.Now().UTC().Format(time.RFC3339)
	if err == nil {
		run.LastOK, run.Error = now, ""
	} else {
		run.LastFailed, run.Error = now, message
	}
	runs[target] = run

	b, mErr := json.MarshalIndent(runs, "", "  ")
	if mErr != nil {
		return
	}
	tmp := backupsPath() + ".tmp"
	if os.WriteFile(tmp, b, 0o640) == nil {
		_ = os.Rename(tmp, backupsPath())
	}
}

// collectBackups is what `status` reports: whether a repo is configured, and each
// target's history. Absent entirely when there is neither — a box that has never been
// set up to back up says so by `configured: false`, not by silence.
func collectBackups() map[string]any {
	_, configured := loadBackupConfig()
	return map[string]any{"configured": configured, "targets": loadBackups()}
}
