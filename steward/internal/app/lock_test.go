package app

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"steward/internal/core"
	"strings"
	"sync"
	"testing"
)

// One act on an app at a time. The lock's whole value is in what it refuses, and in the
// fact that it cannot be left behind — see lock.go.

func lockDir(t *testing.T) {
	t.Helper()
	t.Setenv("STEWARD_APPS_DIR", t.TempDir())
}

func TestAppLockRunsTheAct(t *testing.T) {
	lockDir(t)
	ran := false
	if err := withAppLock("web", func() error { ran = true; return nil }); err != nil {
		t.Fatalf("withAppLock: %v", err)
	}
	if !ran {
		t.Error("the act never ran")
	}
}

// The error is passed through untouched: the lock's job is exclusion, not classification.
func TestAppLockPassesTheActsErrorThrough(t *testing.T) {
	lockDir(t)
	want := errors.New("the deploy itself failed")
	if got := withAppLock("web", func() error { return want }); !errors.Is(got, want) {
		t.Errorf("got %v, want the act's own error", got)
	}
}

// Held once, a second attempt is **refused rather than queued**. Waiting would hold an
// SSH connection open on a deploy that can take minutes.
func TestASecondActOnTheSameAppIsRefusedNotQueued(t *testing.T) {
	lockDir(t)
	inner, released := make(chan struct{}), make(chan struct{})
	var second error

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		_ = withAppLock("web", func() error {
			close(inner)
			<-released // hold it while the second attempt is made
			return nil
		})
	}()

	<-inner
	secondRan := false
	second = withAppLock("web", func() error { secondRan = true; return nil })
	close(released)
	wg.Wait()

	if second == nil {
		t.Fatal("a second act acquired a lock that was already held")
	}
	if secondRan {
		t.Error("the second act ran anyway")
	}
	// It says which app and that the wait is finite — a refusal nobody can act on is
	// just an error message.
	if !strings.Contains(second.Error(), `"web"`) {
		t.Errorf("the refusal does not name the app: %v", second)
	}
	// Retryable: nothing is wrong, something else is simply mid-act.
	var ce *codedError
	if !errors.As(second, &ce) || ce.code != "app_busy" || !ce.retryable {
		t.Errorf("want a retryable app_busy code, got %#v", second)
	}
}

// Per app, not per box: a slow release step on one app must not block every other app
// on the machine.
func TestTwoAppsDoNotBlockEachOther(t *testing.T) {
	lockDir(t)
	inner, released := make(chan struct{}), make(chan struct{})

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		_ = withAppLock("web", func() error { close(inner); <-released; return nil })
	}()

	<-inner
	if err := withAppLock("api", func() error { return nil }); err != nil {
		t.Errorf("a second app was blocked by the first: %v", err)
	}
	close(released)
	wg.Wait()
}

// The lock releases when the process does — including when it is killed. That is why
// there is no `unlock` verb to ship and nothing to clean up: a marker file would need
// both, and someone would eventually have to judge whether the marker was real.
func TestTheLockDiesWithTheProcessThatHeldIt(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_APPS_DIR", dir)
	path := filepath.Join(dir, "web.lock")

	// A separate process takes the lock and is killed without ever releasing it.
	holder := exec.Command("flock", path, "sleep", "30")
	if err := holder.Start(); err != nil {
		t.Skipf("no flock(1) to hold the lock with: %v", err)
	}
	// Wait until it really holds it, rather than sleeping and hoping.
	held := false
	for range 200 {
		if withAppLock("web", func() error { return nil }) != nil {
			held = true
			break
		}
	}
	if !held {
		_ = holder.Process.Kill()
		t.Skip("could not observe flock(1) taking the lock")
	}

	if err := holder.Process.Kill(); err != nil {
		t.Fatalf("kill: %v", err)
	}
	_ = holder.Wait()

	if err := withAppLock("web", func() error { return nil }); err != nil {
		t.Errorf("the lock outlived the process that held it: %v", err)
	}
	// And the file is left in place — removing it would race a caller already waiting
	// on that path.
	if _, err := os.Stat(path); err != nil {
		t.Errorf("the lock file should stay: %v", err)
	}
}

// An invalid name never reaches a filesystem path.
func TestAppLockRefusesAnInvalidName(t *testing.T) {
	lockDir(t)
	ran := false
	if err := withAppLock("../../etc/passwd", func() error { ran = true; return nil }); err == nil {
		t.Error("an invalid app name was accepted")
	}
	if ran {
		t.Error("the act ran under an invalid name")
	}
}

// Refused means *nothing was attempted*, so nothing is recorded — the same shape as the
// balancer-role refusal beside it in `deploy`. A chain entry for an act that never ran
// would be the record describing something that did not happen.
func TestARefusedDeployRecordsNothing(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("STEWARD_APPS_DIR", dir)
	record := filepath.Join(t.TempDir(), "record.jsonl")
	t.Setenv("STEWARD_RECORD", record)

	inner, released := make(chan struct{}), make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		_ = withAppLock("web", func() error { close(inner); <-released; return nil })
	}()
	<-inner

	spec := `{"app":{"image":"img@sha256:` + strings.Repeat("a", 64) +
		`","hostnames":["app.example.com"],"port":8080,"health":"/"}}`
	res := runDeployCmdWithStdin(t, spec)
	close(released)
	wg.Wait()

	if res.Code != "app_busy" {
		t.Fatalf("want app_busy, got %q (%s)", res.Code, res.Message)
	}
	if b, err := os.ReadFile(record); err == nil && len(b) > 0 {
		t.Errorf("a refused deploy wrote to the record:\n%s", b)
	}
}

// runDeployCmdWithStdin drives deployCmd with an envelope on stdin.
func runDeployCmdWithStdin(t *testing.T, spec string) core.Result {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	go func() { _, _ = w.WriteString(spec); _ = w.Close() }()
	old := os.Stdin
	os.Stdin = r
	defer func() { os.Stdin = old; _ = r.Close() }()
	return deployCmd([]string{"web"})
}
