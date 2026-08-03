# One steward per box

> Decided 2026-08-01. One box, one `steward` account, one state dir, one record —
> and the binary itself refuses to act as anyone else. Environments are boxes, not
> contexts.

## The bite that forced it

`userExec` derives everything — `HOME`, `XDG_RUNTIME_DIR`, the Quadlet dir — from the
**effective uid of whoever invoked steward**. Run `deploy` as root and the app installs,
healthy and routed, into *root's* rootless-Podman world: root's quadlet units, root's
containers. A ghost install the real `steward` user has never heard of. This happened.

The old guard refused only bare root; any other user could still scatter the same ghost
state into their own home.

## The decision

**Exactly one steward per box.** One `steward` account (created by `prepare`), one
`/var/lib/steward`, one record, one rights ledger. The mechanism, not the convention:

- **The binary binds itself to the account.** Where a `steward` account exists,
  every non-ceiling command runs as **exactly that uid** — anyone else, root
  included, gets `wrong_user` and the corrective command. Where no account exists
  (dev boxes, CI), only bare root is refused, as before. (`wrongUser` in
  `steward/main.go`, pure and tested.)
- **The gate is on one door.** Both ways into a command — the local CLI and the sshd
  forced command — go through `enter` in `main.go`, which gates and then dispatches.
  This was found broken by the 2026-08-01 audit: `_exec` had its own path and reached
  `dispatch` directly, so `sudo steward deploy` was refused while
  `sudo steward _exec --client x --scope operate` was not — the ghost install, through
  the back door. A second entry point is a second gate to forget. The test asserts the
  refusal via the *record*: an empty record proves the gate ran before any side effect.
- **`doctor` detects the residue.** Containers running under any other uid — the
  per-container `conmon` processes any Podman leaves behind — are flagged as ghost
  containers with the question that matters: *was steward run as the wrong user?*
  The gate refuses new ghosts; this surfaces ones already running.

## Environments are boxes

Dev and prod on one machine was explored as multiple steward users
(`steward-dev` / `steward-prod`, each with its own ledger, record, and Podman world)
and rejected. **Separate environments get separate boxes** — a VM is cheaper than the
design:

- The published-port space is shared — both contexts fight over `127.0.0.1:<port>`.
- `apply-updates` and the maintenance window are box-wide — a dev context could
  patch and reboot the box under prod.
- `machines.name` mirrors the box ([machine-name-mirrors-the-box.md](machine-name-mirrors-the-box.md));
  two contexts would need two names for one box.
- Above all: the box is the trust boundary
  ([machine-ownership.md](machine-ownership.md), dedicated-by-default). Dev/prod
  separated by anything *less* than a box would be the first place the project
  accepted a softer boundary than its own tenant model.

## Roads not taken

- **Multiple steward users per box** — the context model above. Real isolation
  (kernel-enforced, per-user), but the shared edges (ports, updates, naming) leak,
  and it re-litigates the box-is-the-boundary decision.
- **A `--context` flag pinned in the forced command.** Un-forgeable by the client,
  but it separates only the *ledger and record*, not the *runtime* — same user, same
  Podman store, same secret store. The wrong boundary for anything worth separating.
- **Env-var contexts** (`STEWARD_RECORD` etc. already parameterize every path for
  tests). Never a wire-level selector: a caller who chooses `STEWARD_RECORD` chooses
  the record, and invariant 2 dies. The `restrict` forced command keeps client env
  out; that stays load-bearing.

## What this answers preemptively

"Can I run two stewards on one box?" — No, and that's the feature. One account is
why `authorized_keys` is *the* rights ledger, why the record is *the* record, and why
un-bypassability stays small enough for one person to check. If you need another
steward, you need another box.
