# One vilice per box

> Decided 2026-08-01. One box, one `_vilice` account, one state dir, one record.
> Environments are boxes, not contexts.

## The problem

`userExec` derives `HOME`, `XDG_RUNTIME_DIR` and the Quadlet dir from the effective uid of
whoever ran vilice. Run `deploy` as root and the app installs, healthy and routed, into
root's rootless-Podman world — a ghost install `_vilice` has never heard of. This
happened. The old guard refused only bare root.

## The decision

- **The binary binds itself to the account.** Where a `_vilice` account exists, every
  non-root command runs as exactly that uid; anyone else, root included, gets
  `wrong_user` and the corrective command. Where none exists (dev boxes, CI), only bare
  root is refused. (`wrongUser` in `internal/core/dispatch.go`, pure and tested.)
- **The gate is on one door.** The local CLI and the sshd forced command both go through
  `enter`. An audit on 2026-08-01 found `_exec` had its own path: `sudo vilice deploy`
  was refused while `sudo vilice _exec --client x --scope operate` was not. The test
  asserts the refusal through the record: an empty record proves the gate ran before any
  side effect.
- **`doctor` detects the residue.** Containers running under any other uid (their
  `conmon` processes) are flagged as ghost containers.

## Environments are boxes

Dev and prod on one machine as two vilice users was explored and rejected. A VM is
cheaper than the design:

- The published-port space is shared; both would fight over `127.0.0.1:<port>`.
- `apply-updates` and the maintenance window are box-wide; dev could reboot prod.
- `machines.name` mirrors the box
  ([machine-name-mirrors-the-box.md](machine-name-mirrors-the-box.md)).
- The box is the trust boundary ([machine-ownership.md](machine-ownership.md)).
  Separating dev and prod by less than a box would be a softer boundary than the tenant
  model's.

## Roads not taken

- **Multiple vilice users per box.** Real per-user isolation, but ports, updates and
  naming leak.
- **A `--context` flag pinned in the forced command.** The client cannot forge it, but it
  separates only the ledger and record, not the runtime: same user, same Podman store,
  same secret store.
- **Env-var contexts.** `VILICE_RECORD` and the rest parameterize paths for tests. They
  are never a wire-level selector: a caller who chooses `VILICE_RECORD` chooses the
  record, and invariant 2 is gone. `restrict` on the forced command keeps client
  environment out, and the design depends on that.
