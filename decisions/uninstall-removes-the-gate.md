# Uninstall removes the gate, never the runtime

> Decided 2026-08-01. `vilice uninstall` is the inverse of `prepare`: it takes off
> the gate and the scribe and leaves everything running. Settles the shape of the
> "decommissioning" open thread's common case.

## The decision

`vilice uninstall` (root ceiling, next to `harden`/`prepare`) removes exactly what
`prepare` created for the *gate and the scribe*: the snapshot timer, the scoped-key
ledger, the sudoers grant, the binary. It is built on the tenet it proves: **Vilice
is a gate and a scribe, not a runtime** — apps are ordinary Quadlet units under
systemd with plain Caddy routes, so deleting Vilice stops nothing.

Three choices inside that shape:

- **Apps survive by default.** Removing them is an explicit opt-in (`--remove-apps`
  or the y/N prompt), and the teardown runs `vilice remove` *as the _vilice user* —
  root driving Podman directly is the ghost-state mistake
  ([one-vilice-per-box.md](one-vilice-per-box.md)) even on the way out.
- **The record stays.** The `_vilice` user and `/var/lib/vilice` are kept: the
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
  [open/vilice-open-questions.md](open/vilice-open-questions.md).
- **A guided Vilice Console checklist as the only path.** The breakglass tenet says
  recovery — and departure — never depends on the web UI. Vilice Console's Remove
  Machine remains the control-plane half; the box-side act is the CLI's.
- **Uninstall also removing packages** (podman, caddy, restic). They may serve the
  apps that keep running, and removing another tool's substrate is not the gate's
  call — standard tools, standard idiom. Saying so is the ceiling's business; saying
  *which* packages is not — see below.

## Why it exists at all

"Delete Vilice and everything works" was a tenet before it was a command. Making it
a *command* makes it checkable — Agora VII (Exit) applied to the operator: leaving is
one recorded verb, not an archaeology exercise.

## The ceiling does not name the substrate (2026-08-10)

Saying packages stay is right; saying *which* was the ceiling's mistake. `uninstall`
printed "podman, caddy, restic" from a literal in `internal/core`, which went from
merely misplaced to false when roles arrived ([roles-not-packs.md](roles-not-packs.md)):
a `balancer` installs Caddy alone, so the ceiling was telling operators the box kept a
container runtime it had never had.

The ceiling now prints what *it* keeps — the `_vilice` user, `/var/lib/vilice`, the
apps — and asks the app layer for the rest, through the `TeardownNote` seam it already
had. Two roads not taken:

- **Condition the ceiling's copy on `core.Role()`.** The shortest fix, and it leaves the
  fact in the wrong layer: the ceiling would still hold a list that goes stale the day
  the substrate changes, now with a role switch on top.
- **A new `Apps` method per message** (`Kept()` beside `TeardownNote`). The seam is the
  line itself, so every method on it is a claim about what the two layers owe each
  other; "what this layer leaves behind" and "what you must know before it goes" are one
  thing said once. `TeardownNote` writes bullets under the ceiling's "This keeps:" and
  carries both.

The app layer names only tools that are actually on the box, so the line is a report
rather than a claim, and one list in `internal/app/prepare.go` feeds `prepare`'s install
steps, its closing version report, and this note — a role's substrate cannot be
installed and described differently.

Core prose still names substrate where it is *true and useful*: `prepare --help` spells
out what each role installs, and the man page says apps are Quadlet units behind Caddy.
Help is documentation ([help-is-the-documentation.md](help-is-the-documentation.md)) and
an operator reading it deserves the concrete answer; the rule broken here was a claim
about a particular box, not a mention of a tool's name.
