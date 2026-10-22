# Uninstall removes the gate, never the runtime

> Decided 2026-08-01. Settles the common case of the decommissioning thread.

## The decision

`vilice uninstall` (root) is the inverse of `prepare`. It removes the snapshot timer, the
scoped-key ledger, the sudoers grant and the binary. Apps are ordinary Quadlet units with
plain Caddy routes, so deleting Vilice stops nothing. Leaving is one recorded verb.

- **Apps survive by default.** Removing them is opt-in (`--remove-apps` or the y/N
  prompt), and the teardown runs `vilice remove` as `_vilice` — root driving Podman
  directly is the ghost-state mistake ([one-vilice-per-box.md](one-vilice-per-box.md)).
- **The record stays.** The `_vilice` user and `/var/lib/vilice` are kept: the record is
  the box's history. Uninstall is recorded before it runs, so it is the chain's last
  entry.
- **The restic password is shown, not wiped.** The backups outlive the box, and this is
  the last moment the box can hand over the key.

## The ceiling does not name the substrate (2026-08-10)

`uninstall` printed "podman, caddy, restic" from a literal in `internal/core`. That
became false with roles: a balancer installs Caddy alone.

The core now prints what it keeps — the `_vilice` user, `/var/lib/vilice`, the apps — and
asks the app layer for the rest through `TeardownNote`. The app layer names only tools
actually on the box, and one list in `internal/app/prepare.go` feeds `prepare`'s install
steps, its version report, and this note.

Core help still names substrate where it is true in general (`prepare --help` says what
each role installs). The rule broken was a claim about a particular box.

## Roads not taken

- **A full `decommission` verb** (shred `secrets/`, remove the user, reap the record).
  Deferred: hardware retirement is rarer and irreversible, and should not ride on the
  common, reversible act. Tracked in
  [open/vilice-open-questions.md](open/vilice-open-questions.md).
- **A console checklist as the only path.** Departure must not depend on the web UI.
- **Also removing packages.** They may serve the apps that keep running.
- **Condition the core's copy on `core.Role()`.** The list stays in the wrong layer, now
  with a switch on top.
- **A second seam method** (`Kept()` beside `TeardownNote`). Every method on the seam is a
  claim about what the layers owe each other; one note carries both.
