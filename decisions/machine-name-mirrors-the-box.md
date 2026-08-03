# A machine's name mirrors the box, not the operator

> Settled 2026-06-17 while cleaning up the Add Machine form. Builds on
> [machine-onboarding.md](machine-onboarding.md) and
> [observe-reconciliation.md](observe-reconciliation.md).

## The question

Add Machine asked the operator to type a **Machine Name** — a free-text label, separate
from the box's own hostname and from the SSH host you dial. That's a third name for one
thing, and it drifts: the box calls itself `web-1`, you typed `acme prod`, and now the
record, the box, and your head disagree. The name a box answers to should be the box's,
not a sticky note.

## The decision

**The name is not typed. It mirrors the box.**

- The **Machine Name** field is gone from the form.
- At Add time we can't read the box yet — it hasn't authorized our key — so the name is
  **seeded with the SSH host** (`ssh_host`), which is required and always present.
- The **first successful observe renames it** to the box's reported hostname
  (`status.data.machine.hostname`), in the reconcile path that already runs on every read
  ([observe-reconciliation.md](observe-reconciliation.md)).

The rename is guarded so it's a one-time seeding, not churn:

- it only replaces the **still-provisional** name (`name == ssh_host`) — a name already
  mirrored from the box, or set explicitly in seeds/tests, is left alone;
- it never renames to a name **another machine holds** (`name` is uniquely indexed, and
  `update_columns` skips the model validation, so the collision is checked by hand);
- a box whose hostname *equals* its SSH host is a no-op.

`name` stays **required + unique** at the model — the seed guarantees presence at Add
time, and the index still protects the fleet from two boxes claiming one name.

## Why seed from the SSH host, not leave it blank

`name` is the handle the whole UI hangs on (rows, links, the record line) and it's uniquely
indexed — a blank or null name would break the page and the constraint the moment a box is
added, before we've ever reached it. The SSH host is a true, present, unique-enough
identifier for the gap between *added* and *first heard from*, and it reads honestly on
screen ("we know where it is, not yet what it calls itself") until the box answers.

## Roads not taken

- **Keep the typed name.** Rejected: it's a third name that drifts from the box and the
  record, against the plain-naming rule — the operator groups boxes with **labels**, which
  already exist for exactly that and don't pretend to be the machine's identity.
- **Mirror continuously (rename on every read).** Rejected: needless writes, and it would
  fight any future "rename the box" intent. Seed-once (replace only the provisional) gives
  the mirror with none of the churn — and keeps the fake-observe/seed fixtures, whose
  reported hostname is derived from their name, from rewriting themselves on a dev sweep.
- **Read the box during Add to get the real name up front.** Can't — onboarding hands you
  the `authorize` line precisely because we *can't* reach the box yet
  ([machine-onboarding.md](machine-onboarding.md)).
