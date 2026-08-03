# Uninstall removes the gate, never the runtime

> Decided 2026-08-01. `steward uninstall` is the inverse of `prepare`: it takes off
> the gate and the scribe and leaves everything running. Settles the shape of the
> "decommissioning" open thread's common case.

## The decision

`steward uninstall` (root ceiling, next to `harden`/`prepare`) removes exactly what
`prepare` created for the *gate and the scribe*: the snapshot timer, the scoped-key
ledger, the sudoers grant, the binary. It is built on the tenet it proves: **Steward
is a gate and a scribe, not a runtime** — apps are ordinary Quadlet units under
systemd with plain Caddy routes, so deleting Steward stops nothing.

Three choices inside that shape:

- **Apps survive by default.** Removing them is an explicit opt-in (`--remove-apps`
  or the y/N prompt), and the teardown runs `steward remove` *as the steward user* —
  root driving Podman directly is the ghost-state mistake
  ([one-steward-per-box.md](one-steward-per-box.md)) even on the way out.
- **The record stays.** The `steward` user and `/var/lib/steward` are kept: the
  record is the box's history, not the tool's scratch space (Agora II — the history
  is preserved as it was). Uninstall itself is recorded before it runs, so the
  chain's last entry is the uninstall.
- **The restic password is surfaced, not wiped.** Uninstall prints the repo URL and
  password before acting — the backups outlive the box, and this is the last moment
  the box can hand the operator the key to them. Wiping secrets is a *retirement*
  action, deliberately not bundled here.

## Roads not taken

- **A full `decommission` verb** (shred `secrets/`, remove the user, reap the record).
  Deferred, not rejected — it is the *hardware retirement* case, rarer and more
  destructive, and bundling it into uninstall would make the common, reversible act
  carry the irreversible one. The remaining gap stays in
  [open/steward-open-questions.md](open/steward-open-questions.md).
- **A guided Steward Console checklist as the only path.** The breakglass tenet says
  recovery — and departure — never depends on the web UI. Steward Console's Remove
  Machine remains the control-plane half; the box-side act is the CLI's.
- **Uninstall also removing packages** (podman, caddy, restic). They may serve the
  apps that keep running, and removing another tool's substrate is not the gate's
  call — standard tools, standard idiom.

## Why it exists at all

"Delete Steward and everything works" was a tenet before it was a command. Making it
a *command* makes it checkable — Agora VII (Exit) applied to the operator: leaving is
one recorded verb, not an archaeology exercise.
