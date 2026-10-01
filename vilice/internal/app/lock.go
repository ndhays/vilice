package app

// One app's lifecycle runs one at a time.
//
// Two concurrent `deploy web` calls both read the same active colour, both compute the
// same target, both write that colour's unit, and both flip Caddy — and whichever loses
// the race has already torn down the colour the winner is serving from. The console
// driving a box while an operator types is the ordinary case here, not the exotic one
// (the Record makes the same argument for its own flock, in core/audit.go).
//
// **Per app, not per box.** Two different apps do not share state, units, or colours, and
// a release step may legitimately run for minutes — a box-wide lock would let one slow
// migration block every other app on the machine. The residual cross-app race is port
// allocation, noted below.
//
// **flock, so it cannot go stale.** The lock lives on a file descriptor: the kernel drops
// it when the process exits, including on a kill or a severed SSH connection. There is
// nothing to clean up and no `unlock` verb to ship — which is worth saying out loud,
// because a lock implemented as a marker file needs both, and someone eventually has to
// decide whether the marker they are looking at is real.

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"vilice/internal/core"
)

// withAppLock runs fn while holding this app's lifecycle lock, and refuses rather than
// waits when someone else holds it. Waiting would hold an SSH connection open on a
// deploy that may take minutes; refusing says so immediately and leaves the caller to
// decide.
//
// The refusal happens **before** fn — so before anything is recorded, because nothing was
// attempted. The same shape as the balancer-role refusal at the top of `deploy`.
func withAppLock(app string, fn func() error) error {
	if !core.ValidAppName(app) {
		return fmt.Errorf("refusing to lock an invalid app name %q", app)
	}
	if err := os.MkdirAll(appsDir(), 0o750); err != nil {
		return err
	}
	path := filepath.Join(appsDir(), app+".lock")

	// The file is only ever a handle for the lock; nothing is written to it, and it is
	// left in place afterwards. Removing it would race a second caller who has already
	// opened the same path and is waiting to acquire.
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o640) // #nosec G304 -- name validated above
	if err != nil {
		return err
	}
	defer f.Close()

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return &codedError{code: "app_busy", retryable: true, msg: fmt.Sprintf(
			"another act on %q is still running — its lock is held. Wait for it to finish "+
				"and try again; the lock releases on its own, even if that act is killed.", app)}
	}
	// Released with the fd on close. No unlock here: an explicit one would race the
	// deferred close on any path that returns early.

	return fn()
}
