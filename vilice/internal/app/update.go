package app

// update: deploy an app's saved spec again with a new image, and nothing else changed.
//
// It is rollback pointed forward. rollback re-applies the saved spec with the previous
// image and never asks for a secret value — they are already in Podman's store — and
// update does the same with an image you name. Env, secrets, volumes, hostnames,
// stop_first: all of it is the spec the box already holds. That is what lets an app
// update itself (the console, from its Settings page) without ever handling its own
// secrets. See decisions/update-is-rollback-pointed-forward.md.
//
// It runs in the background, because the caller may be the app being replaced: the
// console asks the box to update the console, and blue/green stops the old colour — the
// very process holding the SSH connection — once the new one is healthy. So `update` is
// the act: it is recorded, writes the request beside the app's state, starts a transient
// systemd unit, and answers at once. The unit runs `run-update`, which carries out that
// request and nothing else, and writes how it went where `status` reports it.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"vilice/internal/core"
)

// An update request and how it went. One per app, replaced by the next update.
type updateRequest struct {
	Image       string    `json:"image"`
	Actor       string    `json:"actor"`
	RequestedAt time.Time `json:"requested_at"`
	Unit        string    `json:"unit"`
	// started → running → ok | failed. Only a request still "started" can be run, so
	// the background half cannot be replayed or pointed at something nobody asked for.
	State      string    `json:"state"`
	Message    string    `json:"message,omitempty"`
	FinishedAt time.Time `json:"finished_at,omitempty"`
}

const (
	updateStarted = "started"
	updateRunning = "running"
	updateOK      = "ok"
	updateFailed  = "failed"
)

// Beside the app states, in a folder of its own: listApps reads every *.json in the
// apps folder as an app, and skips folders.
func updatesDir() string            { return filepath.Join(appsDir(), "updates") }
func updatePath(name string) string { return filepath.Join(updatesDir(), name+".json") }

func loadUpdate(name string) (updateRequest, bool) {
	b, err := os.ReadFile(updatePath(name))
	if err != nil {
		return updateRequest{}, false
	}
	var u updateRequest
	if json.Unmarshal(b, &u) != nil {
		return updateRequest{}, false
	}
	return u, true
}

func saveUpdate(name string, u updateRequest) error {
	if err := os.MkdirAll(updatesDir(), 0o750); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(u, "", "  ")
	tmp := updatePath(name) + ".tmp"
	if err := os.WriteFile(tmp, b, 0o640); err != nil {
		return err
	}
	return os.Rename(tmp, updatePath(name))
}

// lastUpdate is the app's last update for status, or nil if it has had none.
func lastUpdate(name string) *updateRequest {
	if u, ok := loadUpdate(name); ok {
		return &u
	}
	return nil
}

func removeUpdate(name string) {
	_ = os.Remove(updatePath(name))
}

// --- update (the act) ---

func updateCmd(args []string) core.Result {
	flags, pos := core.ParseArgs(args)
	name, image := firstPos(pos), flags["image"]
	if name == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}
	// The same two checks deploy makes (validateRenderable): pinned at all, then pinned
	// well. validDigestPin alone passes a tag — it only judges what follows @sha256:.
	if !strings.Contains(image, "@sha256:") {
		return core.Result{Code: "bad_args", Message: "--image must be digest-pinned (ref@sha256:…) — a tag means something different tomorrow"}
	}
	if err := validDigestPin(image); err != nil {
		return core.Result{Code: "bad_args", Message: err.Error()}
	}
	st, found := loadApp(name)
	if !found {
		return core.Result{Code: "not_found", Message: fmt.Sprintf("no app %q — update changes a deployed app's image; deploy it first", name)}
	}
	if st.Image == image {
		return core.Result{Code: "unchanged", Message: fmt.Sprintf("%q already runs %s", name, shortDigest(image))}
	}
	if u, ok := loadUpdate(name); ok && (u.State == updateStarted || u.State == updateRunning) {
		return core.Result{Code: "app_busy", Retryable: true,
			Message: fmt.Sprintf("an update of %q to %s is already %s", name, shortDigest(u.Image), u.State)}
	}

	// The lock is held while the request is written and the unit started, so this does
	// not race a deploy that is mid-flip. The unit takes it again to do the work.
	var started updateRequest
	err := withAppLock(name, func() error {
		started = updateRequest{
			Image: image, Actor: core.ActorName(), RequestedAt: time.Now().UTC(), State: updateStarted,
			Unit: fmt.Sprintf("vilice-update-%s-%d", name, time.Now().Unix()),
		}
		if err := saveUpdate(name, started); err != nil {
			return &codedError{code: "io_error", msg: err.Error()}
		}
		if err := startUpdateUnit(name, started); err != nil {
			started.State, started.Message, started.FinishedAt = updateFailed, err.Error(), time.Now().UTC()
			_ = saveUpdate(name, started)
			return &codedError{code: "update_failed", retryable: true, msg: "could not start the update: " + err.Error()}
		}
		return nil
	})
	return resultOrErr(err, "update_failed", fmt.Sprintf(
		"updating %q to %s in the background (unit %s) — `vilice status --json` shows how it went",
		name, shortDigest(image), started.Unit))
}

// startUpdateUnit runs `vilice run-update <app>` as a transient user unit: owned by the
// _vilice user's systemd, not by this SSH session, so it outlives a caller that goes
// away — including the one being updated. Its output goes to the journal.
var startUpdateUnit = func(name string, u updateRequest) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	out, err := userExec("systemd-run", "--user", "--unit", u.Unit, "--collect", "--quiet",
		"--setenv=VILICE_ACTOR="+u.Actor, exe, "run-update", name).CombinedOutput()
	if err != nil {
		return fmt.Errorf("systemd-run: %s", firstLine(string(out), err))
	}
	return nil
}

// --- run-update (the background half) ---

// Seams for the tests: the deploy itself drives Podman and systemd, and the account
// check needs the box's _vilice user.
var (
	deployForUpdate = runDeploy
	runsAsVilice    = defaultRunsAsVilice
)

func defaultRunsAsVilice() bool { return core.RunsAsVilice() }

func runUpdateCmd(args []string) core.Result {
	_, pos := core.ParseArgs(args)
	name := firstPos(pos)
	if name == "" {
		return core.Result{Code: "bad_args", Message: "missing <app>"}
	}
	// System-scoped, so the gate does not check the account. Run as root, Podman and the
	// units would land in root's home: the ghost install one-vilice-per-box.md prevents.
	if !runsAsVilice() {
		return core.Result{Code: "wrong_user", Message: "run-update runs as the _vilice user, from the unit `update` starts"}
	}
	u, ok := loadUpdate(name)
	if !ok || u.State != updateStarted {
		return core.Result{Code: "no_request", Message: fmt.Sprintf("no update of %q is waiting to run — `vilice update` starts one", name)}
	}
	u.State = updateRunning
	if err := saveUpdate(name, u); err != nil {
		return core.Result{Code: "io_error", Message: err.Error()}
	}

	err := withAppLock(name, func() error {
		st, found := loadApp(name)
		if !found {
			return &codedError{code: "not_found", msg: fmt.Sprintf("app %q is gone", name)}
		}
		st.Image = u.Image
		st.Digest = appDigest(st)
		// The spec changed — its image did — so its digest is recorded, as deploy records
		// its own, before the box is touched. The act itself was recorded when `update` ran.
		if err := core.Record(u.Actor, string(core.ScopeOperate), "update-spec", []string{name, st.Digest}); err != nil {
			return &codedError{code: "record_failed", retryable: true, msg: err.Error()}
		}
		return deployForUpdate(&st)
	})

	u.FinishedAt = time.Now().UTC()
	if err != nil {
		u.State, u.Message = updateFailed, err.Error()
	} else {
		u.State, u.Message = updateOK, ""
	}
	_ = saveUpdate(name, u)
	return resultOrErr(err, "update_failed", fmt.Sprintf("updated %q to %s", name, shortDigest(u.Image)))
}
