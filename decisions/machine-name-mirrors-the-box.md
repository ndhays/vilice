# A machine's name mirrors the box, not the operator

> Decided 2026-06-17. Builds on [machine-onboarding.md](machine-onboarding.md) and
> [observe-reconciliation.md](observe-reconciliation.md).

## The decision

**The name is not typed. It mirrors the box.** A typed name was a third name for one
thing, beside the box's hostname and the SSH host, and it drifted.

- The Machine Name field is gone from Add Machine.
- At Add time the box cannot be read yet, so the name is **seeded with `ssh_host`**.
- The **first successful observe renames it** to the box's reported hostname
  (`status.data.machine.hostname`), in the reconcile path.

The rename is a one-time seeding:

- it replaces only the still-provisional name (`name == ssh_host`);
- it never takes a name another machine holds (`update_columns` skips validation, so the
  collision is checked by hand);
- a box whose hostname equals its SSH host is a no-op.

`name` stays required and unique at the model.

## Why seed from the SSH host

`name` is the handle the UI hangs on and it is uniquely indexed; a blank one would break
the page and the constraint. The SSH host is true, present, and unique enough for the gap
between *added* and *first heard from*.

## Roads not taken

- **Keep the typed name.** Operators group boxes with labels, which do not pretend to be
  the machine's identity.
- **Mirror on every read.** Needless writes; it would fight a future "rename the box"; and
  seed fixtures, whose hostname derives from their name, would rewrite themselves.
- **Read the box during Add.** Not possible — the box has not authorized the key yet.
