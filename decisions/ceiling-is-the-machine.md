# The ceiling is the machine, not the rights ledger

**Decided 2026-06-08.** Still canonical, with one part overturned: **"The cost we
accept" below was later declined** — the top rung no longer carries a shell, and is
renamed `ssh` → `grant`. See [no-key-gets-a-shell.md](no-key-gets-a-shell.md). Read
`ssh` as `grant` throughout; the reasoning about *where the ceiling sits* is unchanged
and is the part that matters here.

Only two commands need root: `prepare` and `harden` — the ones that change the
*machine*. Every other Steward command, **including `authorize` and `revoke`**, runs as
the unprivileged `steward` user. This narrows the legible ceiling (invariant 3) to the
machine and the record, and removes root from day-to-day operation entirely.

## The two tiers

| Runs as | Commands | Because |
|---|---|---|
| **root** | `prepare`, `harden` | They mutate the machine — apt, `useradd`, sshd, systemd units, `chattr` on the record floor. |
| **`steward`** | `authorize`, `revoke`, `deploy`/`rollback`/`start`/`stop`/`remove`, `status`, `logs`, `doctor`, `snapshot` | They touch only files and services the `steward` user owns. |

`prepare` is the genesis exception: it *creates* the `steward` user (`ensureStewardUser`),
so it cannot itself run as that user. Everything after it can.

## Why `authorize`/`revoke` left the ceiling

They do one thing: edit `~steward/.ssh/authorized_keys` — steward's **own** file.
Writing your own file is not a privileged act. Running them as the `steward` user means:

- no root, no `sudo`, no named-admin layer to maintain;
- `authorizedKeysPath()` (`os.UserHomeDir()`) resolves `/home/steward` **by
  construction** — the existing code is correct once the caller is `steward`;
- scoped keys land in `steward`'s `authorized_keys`, not root's — which answers half of
  the Container-user-model open question (whom scoped keys authenticate as).

## Granting is the top of the ladder, not a wall above it

This overturns the earlier rationale in [provision.md](../blueprint/steward/provision.md)
("if a scoped key could run `authorize`, the gate could rebuild its own gate, so they
are root-only"). The objection assumes *any* scoped key could then grant. It can't.

The ladder `observe ⊂ operate ⊂ ssh` means what it says: only an **`ssh`-scope** grant
yields an accountable shell as `steward`, and only from that shell can you run
`authorize`/`revoke`. `observe` and `operate` keys are pinned by their forced command to
their own scope and never reach a shell — they **cannot** grant. So no *escalation* path
opens: the only actor who can rebuild the rights ledger is one already trusted at the
top rung.

The correction is about *what* must stay un-rebuildable. It is **the machine and the
record floor** — not the rights ledger:

- **Machine** — `prepare`/`harden`, root-only, no key reaches them. Replacing Steward
  itself stays *below* Steward (systemd + the god-key bootstrap), never through it.
- **Record** — the append-only floor (`chattr +a`) refuses even the `steward` user; it
  can only be appended to.
- **Rights ledger** — steward's own file, governed by the ladder. `ssh`-scope sits at
  its top (Article IV: rights declared and inspectable, granted by the top rung).

## The cost we accept — ✗ **later declined** (2026-08-02)

> **Superseded by [no-key-gets-a-shell.md](no-key-gets-a-shell.md).** The reasoning
> below is sound about *persistence* and wrong about *scale*: the unrecorded surface a
> shell opens is not just the rights ledger, it is every action the box can take, which
> put an asterisk on un-bypassability itself. The top rung kept its job and lost the
> shell. What remains true is the last bullet — the record floor and the machine ceiling
> stay out of reach — and the `steward`-user *compromise* case, which no scope change
> can fix. Kept here as written, because a declined cost is worth reading.

A shell-as-`steward` actor (an `ssh`-scope grant, or a `steward`-user compromise) can
edit `authorized_keys` directly — out of band, unrecorded by Steward. We accept this:

- `ssh`-scope already means "near-total, recorded as a *shell grant*, not per-keystroke."
  This is not a new exposure; it is what `--scope ssh` always meant.
- Such an actor already has arbitrary code as `steward` **and** lingering user services,
  so key-based persistence is marginal on top of what they can already do.
- The two things that actually bound blast radius — the record floor and the machine
  ceiling — stay out of reach.

## Corollaries

- **Refuse bare root.** Every command except `prepare`/`harden` — and `snapshot`, the
  machine-invoked recorder (see next) — refuses `euid 0`, with a `sudo -u steward …`
  hint. `prepare`'s closing banner prints the first such command so the bootstrap
  hand-off is discoverable.
- **Snapshot stays root until rootless Podman.** Long-term the timer runs as `steward`
  (the containers become steward's under rootless Podman). Until that migration `deploy`
  runs Podman as root, so the snapshot must too — `collectApps()` reads `podman ps` as
  the calling user. So `scopeSystem` is exempt from the bare-root refusal for now, and
  flipping the timer to `User=steward` rides with the Container-user-model migration,
  not this change.
- **`PermitRootLogin no` becomes viable.** No scoped traffic needs root anymore. The
  `harden` ssh step closes root SSH **automatically when safe**: it disables root login
  iff a non-root, key-capable account already exists (a generic uid≥1000 user with a
  login shell and an `authorized_keys`); otherwise it keeps `prohibit-password`, so a
  fresh box — where root is the only account — is never locked out. SSH only: the root
  *password* is left intact as a console break-glass (we did **not** add `passwd -dl
  root`). The lockout guard is generalized from "root has a key" to "*someone* has a
  key."

## Road not taken: keep `authorize`/`revoke` root, behind a named `sudo` admin

The alternative (option B): granting stays a true-root ceiling; an admin logs in as a
*named* user and runs `sudo steward authorize …`, with `SUDO_USER` recorded as the
actor. Rejected:

- it re-imports a whole named-admin + sudoers layer to protect a file steward already
  owns;
- the marginal protection (stopping a `steward`-user compromise from persisting via
  keys) is small, given such a compromise already has code execution and lingering
  services as `steward`;
- it keeps root in the everyday loop — exactly what this decision removes.

Kept as the fallback if granting ever needs to be a hard wall *above* `operate` — e.g. a
multi-tenant or delegated-fleet model where holding `operate` must never imply the
ability to mint new keys.

## Refinement: two scope axes, and `apply-updates`' narrow root grant (2026-06-11)

This decision conflated two *different* scope axes, and it bit `apply-updates`:

- **Client / SSH scope** (`observe ⊂ operate ⊂ ssh`) — what a *remote caller* may
  **invoke**, enforced by `authorized_keys` forced-commands.
- **On-box privilege** (`steward` user ⊂ root) — what the invoked command *needs
  locally* to do its job.

They are orthogonal. Making "everything but `prepare`/`harden` run as the `steward`
user" is right for the first axis, but it left **no escalation path for the one
operate command that genuinely needs root on the second** — `apply-updates` (apt).
The result was a hard contradiction: dispatch refused it as root (operate ⇒
`needsStewardUser`), and the command refused to run as non-root — so it was
**un-runnable both ways**.

**Fix:** keep `apply-updates` operate-scoped, and give the `steward` user a *narrow,
inspectable* root escalation — `prepare` lays `/etc/sudoers.d/steward` allowing
exactly `apt-get update -y` and `apt-get upgrade -y` (and nothing else); the command
runs them via `sudo -n` when not root. The grant is as legible as `authorized_keys`,
so the ceiling stays small. A box prepared before this fix just needs `prepare`
re-run (idempotent).

**Road not taken:** move `apply-updates` to the root tier — rejected, because then it
could not be issued over scoped SSH (which authenticates as `steward`), breaking the
remote operate flow the whole model depends on.

**Audit (same date):** `apply-updates` was the *only* straggler — every other
operate/observe command was already rootless (deploy/lifecycle/remove via rootless
Podman + Caddy's admin API + `systemctl --user`; authorize/revoke editing
`~steward/.ssh`; record/verify on the steward-owned append-only floor; status/logs/
doctor; backup/restore via restic on steward-readable data).
