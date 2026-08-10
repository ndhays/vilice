package app

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// Uninstall's parting note must point at the restic password, never print it. The
// secret used to go to stdout, which is terminal scrollback, the systemd journal, and
// the log of any automation that ran `uninstall --yes`. The file survives uninstall,
// so the operator who needs it can still read it.
func TestUninstallNotePointsAtThePasswordWithoutPrintingIt(t *testing.T) {
	const password = "correct-horse-battery-staple"
	dir := t.TempDir()
	t.Setenv("STEWARD_RECORD", filepath.Join(dir, "record.log")) // stateDir/secretsDir derive from this
	t.Setenv("STEWARD_BACKUP_CONFIG", filepath.Join(dir, "backup.json"))
	t.Setenv("STEWARD_SECRETS_DIR", filepath.Join(dir, "secrets"))

	if err := os.WriteFile(backupConfigPath(), []byte(`{"repo":"s3:example.com/bucket"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(secretsDir(), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(resticPasswordFile(), []byte(password+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	// printBackupNote became the layer's TeardownNote, which writes to a Writer the
	// ceiling supplies rather than straight to stdout. Same note, same assertions.
	var note bytes.Buffer
	New().TeardownNote(&note)
	out := note.String()

	if strings.Contains(out, password) {
		t.Errorf("the restic password was printed:\n%s", out)
	}
	for _, want := range []string{resticPasswordFile(), "s3:example.com/bucket"} {
		if !strings.Contains(out, want) {
			t.Errorf("the note should mention %q; got:\n%s", want, out)
		}
	}
}

// captureStdout runs fn with os.Stdout redirected and returns what it wrote.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	saved := os.Stdout
	os.Stdout = w
	done := make(chan string, 1)
	go func() {
		b, _ := io.ReadAll(r)
		done <- string(b)
	}()
	fn()
	os.Stdout = saved
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return <-done
}

func TestVolumeSource(t *testing.T) {
	cases := map[string]string{
		"data:/var/lib/db":    "data",   // named volume
		"data:/var/lib/db:ro": "data",   // named + options
		"/srv/x:/data":        "/srv/x", // bind mount
		"/srv/x:/data:ro,Z":   "/srv/x", // bind + options
		"lonely":              "lonely", // bare token, no dest
	}
	for in, want := range cases {
		if got := volumeSource(in); got != want {
			t.Errorf("volumeSource(%q) = %q, want %q", in, got, want)
		}
	}
}

// Bind-mount sources resolve to their host path with no podman call; named volumes
// (which need `podman volume inspect`) are exercised on the box.
func TestVolumeDirsBindMounts(t *testing.T) {
	st := appState{Name: "web", Volumes: []string{"/srv/a:/data:ro", "/srv/b:/x"}}
	dirs, err := volumeDirs(st)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"/srv/a", "/srv/b"}; !reflect.DeepEqual(dirs, want) {
		t.Errorf("volumeDirs = %v, want %v", dirs, want)
	}
}

func TestLoadBackupConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "backup.json")
	t.Setenv("STEWARD_BACKUP_CONFIG", path)

	if _, ok := loadBackupConfig(); ok {
		t.Error("absent config should report ok=false")
	}

	if err := os.WriteFile(path, []byte(`{"repo":""}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, ok := loadBackupConfig(); ok {
		t.Error("empty repo should report ok=false (not configured)")
	}

	if err := os.WriteFile(path, []byte(`{"repo":"/srv/restic"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	c, ok := loadBackupConfig()
	if !ok || c.Repo != "/srv/restic" {
		t.Errorf("loadBackupConfig = %+v, %v; want repo=/srv/restic, ok", c, ok)
	}
}

// Backup/restore refuse cleanly (not crash) when no repo is configured.
func TestBackupNotConfigured(t *testing.T) {
	t.Setenv("STEWARD_BACKUP_CONFIG", filepath.Join(t.TempDir(), "nope.json"))
	if r := backupCmd([]string{"web"}); r.Code != "not_configured" {
		t.Errorf("backup without config: code = %q, want not_configured", r.Code)
	}
	if r := restoreCmd([]string{"web"}); r.Code != "not_configured" {
		t.Errorf("restore without config: code = %q, want not_configured", r.Code)
	}
}

func TestResticPasswordFileUnderSecretsDir(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_SECRETS_DIR", dir)
	if got, want := resticPasswordFile(), filepath.Join(dir, "restic"); got != want {
		t.Errorf("resticPasswordFile = %q, want %q", got, want)
	}
}
