package app

// `backup` / `restore` (operate): encrypted, deduplicated backups via restic. Steward
// backs up an app's declared volumes plus its spec (so a snapshot is self-contained:
// data + how to redeploy), and can snapshot its own record dir off-box. It stays
// database-agnostic — an app that needs a consistent dump declares a backup hook
// (see deploy.go); Steward never learns what Postgres or SQLite is.
//
// restic encrypts client-side with an operator-held key, so the destination only ever
// sees ciphertext — the repo can live on hostile infra and stay sovereign. The repo URL
// (not secret) lives in backup.json; the password (secret) lives in its own 0600 file,
// passed via RESTIC_PASSWORD_FILE, never on argv. See decisions/backup.md.

import (
	"steward/internal/core"

	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// backupConfig is the per-machine restic target.
type backupConfig struct {
	Repo string `json:"repo"`
}

func backupConfigPath() string {
	if p := os.Getenv("STEWARD_BACKUP_CONFIG"); p != "" {
		return p
	}
	return "/var/lib/steward/backup.json"
}

func secretsDir() string {
	if p := os.Getenv("STEWARD_SECRETS_DIR"); p != "" {
		return p
	}
	return "/var/lib/steward/secrets"
}

func resticPasswordFile() string { return filepath.Join(secretsDir(), "restic") }

// stateDir is Steward's own state home (/var/lib/steward), derived from the record path
// so a test override moves them together.
func stateDir() string { return filepath.Dir(core.RecordPath()) }

func machineID() string {
	b, err := os.ReadFile("/etc/machine-id")
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// loadBackupConfig reads the configured repo. ok=false (not an error) when unconfigured.
func loadBackupConfig() (backupConfig, bool) {
	b, err := os.ReadFile(backupConfigPath()) // #nosec G304 -- steward's own configured path
	if err != nil {
		return backupConfig{}, false
	}
	var c backupConfig
	if json.Unmarshal(b, &c) != nil || c.Repo == "" {
		return backupConfig{}, false
	}
	return c, true
}

// resticCmd runs restic as the steward user with the repo + password file in the
// environment (never argv). The password rides RESTIC_PASSWORD_FILE.
func resticCmd(cfg backupConfig, args ...string) *exec.Cmd {
	c := userExec("restic", args...)
	c.Env = setEnv(c.Env, "RESTIC_REPOSITORY", cfg.Repo)
	c.Env = setEnv(c.Env, "RESTIC_PASSWORD_FILE", resticPasswordFile())
	return c
}

// --- dispatch ---

func backupCmd(args []string) core.Result {
	flags, pos := core.ParseArgs(args)

	// `backup --repo <url>` configures the repo and reads the password on stdin.
	if repo, ok := flags["repo"]; ok {
		return configureBackup(repo)
	}

	cfg, ok := loadBackupConfig()
	if !ok {
		return core.Result{Code: "not_configured",
			Message: "no backup repo configured — run: steward backup --repo <url>  (password on stdin)"}
	}

	if _, machine := flags["machine"]; machine {
		return backupMachine(cfg)
	}
	if _, all := flags["all"]; all {
		return backupAll(cfg)
	}
	app := firstPos(pos)
	if app == "" {
		return core.Result{Code: "bad_args", Message: "missing <app> (or --all / --machine)"}
	}
	st, ok := loadApp(app)
	if !ok {
		return core.Result{Code: "not_found", Message: fmt.Sprintf("no such app %q", app)}
	}
	return backupApp(cfg, st)
}

func restoreCmd(args []string) core.Result {
	flags, pos := core.ParseArgs(args)
	cfg, ok := loadBackupConfig()
	if !ok {
		return core.Result{Code: "not_configured",
			Message: "no backup repo configured — run: steward backup --repo <url>"}
	}
	if _, machine := flags["machine"]; machine {
		return restoreMachine(cfg)
	}
	app := firstPos(pos)
	if app == "" {
		return core.Result{Code: "bad_args", Message: "missing <app> (or --machine)"}
	}
	snapshot := flags["snapshot"]
	if snapshot == "" {
		snapshot = "latest"
	}
	return restoreApp(cfg, app, snapshot)
}

// --- configure ---

// configureBackup writes the repo to backup.json and the stdin password to the 0600
// password file, then inits the repo if it's new.
func configureBackup(repo string) core.Result {
	if repo == "" {
		return core.Result{Code: "bad_args",
			Message: "--repo requires a value (the restic repository, e.g. s3:… or /srv/restic)"}
	}
	pw, err := io.ReadAll(os.Stdin)
	if err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	pw = []byte(strings.TrimRight(string(pw), "\n"))
	if len(strings.TrimSpace(string(pw))) == 0 {
		return core.Result{Code: "bad_args", Message: "backup --repo reads the repo password on stdin — none was provided"}
	}
	if err := os.MkdirAll(secretsDir(), 0o700); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if err := os.WriteFile(resticPasswordFile(), pw, 0o600); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	cfg := backupConfig{Repo: repo}
	b, _ := json.MarshalIndent(cfg, "", "  ")
	if err := os.MkdirAll(filepath.Dir(backupConfigPath()), 0o750); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if err := os.WriteFile(backupConfigPath(), append(b, '\n'), 0o644); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	// Init the repo only if it isn't one already (`cat config` succeeds on a live repo).
	if err := resticCmd(cfg, "cat", "config").Run(); err != nil {
		if out, err := resticCmd(cfg, "init").CombinedOutput(); err != nil {
			return core.Result{Code: "backup_failed", Retryable: true, Message: "restic init: " + strings.TrimSpace(string(out))}
		}
	}
	return core.OK("backup configured — repo " + repo)
}

// --- app backup / restore ---

func backupAll(cfg backupConfig) core.Result {
	apps, err := listApps()
	if err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}
	if len(apps) == 0 {
		return core.OK("no apps to back up")
	}
	var failed []string
	for _, st := range apps {
		if r := backupApp(cfg, st); r.Code != "ok" {
			failed = append(failed, st.Name)
		}
	}
	if len(failed) > 0 {
		return core.Result{Code: "backup_failed", Retryable: true,
			Message: "backed up " + fmt.Sprint(len(apps)-len(failed)) + "/" + fmt.Sprint(len(apps)) +
				" apps; failed: " + strings.Join(failed, ", ")}
	}
	return core.OK(fmt.Sprintf("backed up %d app(s)", len(apps)))
}

func backupApp(cfg backupConfig, st appState) core.Result {
	// Let a stateful app make itself consistent first (e.g. dump a DB into a volume).
	// Steward stays database-agnostic — the app owns this; we just run it in-container.
	if st.Backup != "" && st.ActiveColor != "" {
		container := containerName(st.Name, st.ActiveColor)
		if out, err := userExec("podman", "exec", container, "sh", "-lc", st.Backup).CombinedOutput(); err != nil {
			return core.Result{Code: "backup_failed", Retryable: true,
				Message: "backup hook: " + strings.TrimSpace(string(out))}
		}
	}
	dirs, err := volumeDirs(st)
	if err != nil {
		return core.Result{Code: "backup_failed", Message: err.Error()}
	}
	// Spec file rides along so a snapshot is self-contained: data + how to redeploy.
	paths := append(dirs, appPath(st.Name))
	args := append([]string{"backup",
		"--tag", "app=" + st.Name,
		"--tag", "digest=" + st.Digest,
		"--tag", "host=" + machineID(),
	}, paths...)
	if out, err := resticCmd(cfg, args...).CombinedOutput(); err != nil {
		return core.Result{Code: "backup_failed", Retryable: true, Message: strings.TrimSpace(string(out))}
	}
	return core.OK(fmt.Sprintf("backed up %q (%d volume(s))", st.Name, len(dirs)))
}

// restoreApp puts an app's data and spec back, then redeploys it.
//
// A restore is a write into the live filesystem, so *what the repo is allowed to write*
// is a boundary, not a detail. restic puts absolute paths back where they were, so the
// target is `/` — but the paths that come out are the snapshot's, and a snapshot is
// only as trustworthy as the repo it came from. Left unbounded, a repo could drop a
// file anywhere the steward user can write: ~steward/.ssh/authorized_keys is an ssh
// grant, ~steward/.config/containers/systemd is arbitrary units. So the restore is
// confined with --include to exactly this app's declared paths — its spec file and its
// declared volumes — and nothing else in the snapshot is extracted.
// See decisions/rendered-config-is-a-boundary.md.
func restoreApp(cfg backupConfig, app, snapshot string) core.Result {
	// The spec drives what may be written, so it has to be in hand first. Prefer the
	// one on the box; otherwise take *only* the spec file out of the snapshot.
	st, found := loadApp(app)
	if !found {
		if out, err := resticCmd(cfg, "restore", snapshot, "--tag", "app="+app,
			"--target", "/", "--include", appPath(app)).CombinedOutput(); err != nil {
			return core.Result{Code: "restore_failed", Retryable: true, Message: strings.TrimSpace(string(out))}
		}
		if st, found = loadApp(app); !found {
			return core.Result{Code: "restore_failed", Message: "no spec for " + app + " in that snapshot"}
		}
	}
	// The spec may have come from the repo, so it is an input like any other.
	if err := validateState(st); err != nil {
		return core.Result{Code: "restore_failed",
			Message: fmt.Sprintf("the spec for %q in that snapshot is not valid: %v", app, err)}
	}

	// Register named volumes before resolving their mountpoints (create is
	// metadata-only when the _data dir already exists — it does not wipe contents).
	for _, v := range st.Volumes {
		if src := volumeSource(v); src != "" && !strings.HasPrefix(src, "/") {
			_ = userExec("podman", "volume", "create", src).Run()
		}
	}
	dirs, err := volumeDirs(st)
	if err != nil {
		return core.Result{Code: "restore_failed", Message: err.Error()}
	}

	args := []string{"restore", snapshot, "--tag", "app=" + app, "--target", "/"}
	for _, p := range append(dirs, appPath(app)) {
		args = append(args, "--include", p)
	}
	if out, err := resticCmd(cfg, args...).CombinedOutput(); err != nil {
		return core.Result{Code: "restore_failed", Retryable: true, Message: strings.TrimSpace(string(out))}
	}

	if err := runDeploy(&st); err != nil {
		return core.Result{Code: "restore_failed", Retryable: true, Message: "redeploy: " + err.Error()}
	}
	msg := fmt.Sprintf("restored %q", app)
	if len(st.Secrets) > 0 || len(st.SecretFiles) > 0 {
		msg += " — secret values aren't in backups; redeploy with the secret envelope to repopulate them"
	}
	return core.OK(msg)
}

// --- machine (record) backup / restore ---

func backupMachine(cfg backupConfig) core.Result {
	// Snapshot Steward's own state (record, status, hardening, app specs) off-box.
	// NEVER the secrets dir — don't back the restic password into the repo it unlocks,
	// and don't ship operational secrets.
	args := []string{"backup", stateDir(),
		"--tag", "machine=" + machineID(),
		"--exclude", secretsDir(),
	}
	if out, err := resticCmd(cfg, args...).CombinedOutput(); err != nil {
		return core.Result{Code: "backup_failed", Retryable: true, Message: strings.TrimSpace(string(out))}
	}
	return core.OK("backed up the machine record (" + stateDir() + ", excluding secrets)")
}

func restoreMachine(cfg backupConfig) core.Result {
	// Confined to the state dir it backed up, for the reason restoreApp is: the
	// snapshot's paths decide what gets written, and --include is what keeps that
	// inside Steward's own state instead of anywhere the steward user can reach.
	args := []string{"restore", "latest", "--tag", "machine=" + machineID(),
		"--target", "/", "--include", stateDir(), "--exclude", secretsDir()}
	if out, err := resticCmd(cfg, args...).CombinedOutput(); err != nil {
		return core.Result{Code: "restore_failed", Retryable: true, Message: strings.TrimSpace(string(out))}
	}
	return core.OK("restored the machine record from the latest snapshot")
}

// --- volume resolution ---

// volumeSource is the part of a `Volume=<src>:<dst>[:opts]` spec before the container
// path: a named volume ("data:/var/lib/db" → "data") or a host path ("/srv/x:/data" →
// "/srv/x"). A bare token with no ":" is returned as-is.
func volumeSource(v string) string {
	if i := strings.IndexByte(v, ':'); i >= 0 {
		return v[:i]
	}
	return v
}

// volumeDirs resolves each declared volume's source to a host directory restic can read:
// a named volume via its podman mountpoint, a bind mount as its host path.
func volumeDirs(st appState) ([]string, error) {
	var dirs []string
	for _, v := range st.Volumes {
		src := volumeSource(v)
		if src == "" {
			continue
		}
		if strings.HasPrefix(src, "/") {
			dirs = append(dirs, src) // bind mount
			continue
		}
		out, err := podmanOutput("volume", "inspect", "--format", "{{.Mountpoint}}", src)
		if err != nil {
			return nil, fmt.Errorf("inspect volume %q: %s", src, strings.TrimSpace(out))
		}
		dirs = append(dirs, strings.TrimSpace(out))
	}
	return dirs, nil
}
