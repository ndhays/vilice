package app

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// update is rollback pointed forward: the saved spec, a new image, nothing sent. These
// cover the bookkeeping around the deploy — what is refused, what is written, what the
// background half will and will not run. The deploy itself is runDeploy, tested by its
// own path; here it is a stand-in.

const (
	oldImage = "ghcr.io/acme/web@sha256:1111111111111111111111111111111111111111111111111111111111111111"
	newImage = "ghcr.io/acme/web@sha256:2222222222222222222222222222222222222222222222222222222222222222"
)

func updateBox(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("VILICE_APPS_DIR", filepath.Join(dir, "apps"))
	t.Setenv("VILICE_RECORD", filepath.Join(dir, "record.log"))
	t.Setenv("VILICE_ACTOR", "build-pc")
	st, err := stateFromSpec("web", appSpec{Image: oldImage, Hostnames: []string{"web.example.com"},
		Env: map[string]string{"MODE": "prod"}, Secrets: []string{"TOKEN"}, Volumes: []string{"data:/data"}})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		t.Fatal(err)
	}
	if err := saveApp(st); err != nil {
		t.Fatal(err)
	}
	return dir
}

// stubUnit records what update would start, without systemd.
func stubUnit(t *testing.T, fail error) *[]string {
	t.Helper()
	var started []string
	orig := startUpdateUnit
	startUpdateUnit = func(name string, u updateRequest) error {
		started = append(started, name+" "+u.Image+" "+u.Actor)
		return fail
	}
	t.Cleanup(func() { startUpdateUnit = orig })
	return &started
}

func TestUpdateRefusesWhatItCannotDo(t *testing.T) {
	updateBox(t)
	stubUnit(t, nil)
	cases := map[string][]string{
		"bad_args":  {"web", "--image", "ghcr.io/acme/web:latest"}, // a tag, not a digest
		"not_found": {"nope", "--image", newImage},
		"unchanged": {"web", "--image", oldImage},
	}
	for code, args := range cases {
		if res := updateCmd(args); res.Code != code {
			t.Errorf("update %v: got %q (%s), want %q", args, res.Code, res.Message, code)
		}
	}
	if _, ok := loadUpdate("web"); ok {
		t.Error("a refused update must leave no request behind")
	}
}

func TestUpdateRecordsTheRequestAndStartsTheUnit(t *testing.T) {
	updateBox(t)
	started := stubUnit(t, nil)

	res := updateCmd([]string{"web", "--image", newImage})
	if res.Code != "ok" {
		t.Fatalf("update: %s %s", res.Code, res.Message)
	}
	u, ok := loadUpdate("web")
	if !ok || u.State != updateStarted || u.Image != newImage || u.Actor != "build-pc" {
		t.Fatalf("request = %+v", u)
	}
	if !strings.HasPrefix(u.Unit, "vilice-update-web-") {
		t.Errorf("unit %q", u.Unit)
	}
	if len(*started) != 1 || (*started)[0] != "web "+newImage+" build-pc" {
		t.Errorf("started %v", *started)
	}
	// One at a time: a second update while this one waits is refused.
	if res := updateCmd([]string{"web", "--image", newImage[:len(newImage)-1] + "3"}); res.Code != "app_busy" {
		t.Errorf("second update: %q, want app_busy", res.Code)
	}
	// The request lives beside the app states without becoming one.
	apps, _ := listApps()
	if len(apps) != 1 || apps[0].Name != "web" {
		t.Errorf("listApps = %+v; an update request must not read as an app", apps)
	}
}

func TestUpdateThatCannotStartSaysSoAndLeavesNothingWaiting(t *testing.T) {
	updateBox(t)
	stubUnit(t, errors.New("Failed to connect to bus"))
	res := updateCmd([]string{"web", "--image", newImage})
	if res.Code != "update_failed" || !strings.Contains(res.Message, "bus") {
		t.Errorf("got %q: %s", res.Code, res.Message)
	}
	if u, _ := loadUpdate("web"); u.State != updateFailed {
		t.Errorf("request state %q, want failed — nothing may be left for run-update to pick up", u.State)
	}
}

func TestRunUpdateDeploysTheSavedSpecWithTheNewImage(t *testing.T) {
	dir := updateBox(t)
	stubUnit(t, nil)
	runsAsVilice = func() bool { return true }
	t.Cleanup(func() { runsAsVilice = defaultRunsAsVilice })
	var deployed appState
	deployForUpdate = func(st *appState) error { deployed = *st; return nil }
	t.Cleanup(func() { deployForUpdate = runDeploy })

	if res := updateCmd([]string{"web", "--image", newImage}); res.Code != "ok" {
		t.Fatal(res.Message)
	}
	if res := runUpdateCmd([]string{"web"}); res.Code != "ok" {
		t.Fatalf("run-update: %s %s", res.Code, res.Message)
	}

	// Everything but the image is the spec the box already held — no secret sent.
	if deployed.Image != newImage || deployed.Env["MODE"] != "prod" || deployed.Secrets[0] != "TOKEN" ||
		deployed.Volumes[0] != "data:/data" || deployed.Hostnames[0] != "web.example.com" {
		t.Errorf("deployed %+v", deployed)
	}
	if deployed.Digest != appDigest(deployed) {
		t.Error("the digest must be the new spec's, not the old one's")
	}
	if u, _ := loadUpdate("web"); u.State != updateOK || u.FinishedAt.IsZero() {
		t.Errorf("outcome %+v", u)
	}
	record, _ := os.ReadFile(filepath.Join(dir, "record.log"))
	if !strings.Contains(string(record), "update-spec") || !strings.Contains(string(record), deployed.Digest) {
		t.Errorf("the new spec's digest must be recorded before the box is touched:\n%s", record)
	}

	// Done means done: the same request cannot be run twice.
	if res := runUpdateCmd([]string{"web"}); res.Code != "no_request" {
		t.Errorf("replay: %q, want no_request", res.Code)
	}
}

func TestRunUpdateKeepsTheFailureForWhoeverAsked(t *testing.T) {
	updateBox(t)
	stubUnit(t, nil)
	runsAsVilice = func() bool { return true }
	t.Cleanup(func() { runsAsVilice = defaultRunsAsVilice })
	deployForUpdate = func(*appState) error { return errors.New("health check failed, old app left running") }
	t.Cleanup(func() { deployForUpdate = runDeploy })

	updateCmd([]string{"web", "--image", newImage})
	if res := runUpdateCmd([]string{"web"}); res.Code == "ok" {
		t.Fatal("a failed deploy must not report ok")
	}
	u, _ := loadUpdate("web")
	if u.State != updateFailed || !strings.Contains(u.Message, "old app left running") {
		t.Errorf("outcome %+v", u)
	}
	if st, _ := loadApp("web"); st.Image != oldImage {
		t.Errorf("the saved spec must still name the old image, got %s", st.Image)
	}
	if got := withDeployed(nil, []appState{{Name: "web", Image: oldImage}}); got[0].Update == nil || got[0].Update.State != updateFailed {
		t.Errorf("status must carry the last update: %+v", got)
	}
}

// Run as anyone but _vilice, Podman state would land in that user's home.
func TestRunUpdateRefusesTheWrongAccount(t *testing.T) {
	updateBox(t)
	runsAsVilice = func() bool { return false }
	t.Cleanup(func() { runsAsVilice = defaultRunsAsVilice })
	if res := runUpdateCmd([]string{"web"}); res.Code != "wrong_user" {
		t.Errorf("got %q", res.Code)
	}
}
