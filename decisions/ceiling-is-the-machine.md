# The ceiling is the machine, not the rights ledger

> Decided 2026-06-08. One part was later overturned: the top rung no longer carries a
> shell and is named `grant`, not `ssh` ([no-key-gets-a-shell.md](no-key-gets-a-shell.md)).
> This doc uses the current names.

## The decision

Only the commands that change the *machine* need root. Everything else, **including
`authorize` and `revoke`**, runs as the unprivileged `_vilice` user. The ceiling
(invariant 3) is the machine and the record.

| Runs as | Commands | Because |
|---|---|---|
| **root** | `prepare`, `harden` | They mutate the machine — apt, `useradd`, sshd, systemd units, `chattr` on the record floor. |
| **`_vilice`** | `authorize`, `revoke`, deploy and lifecycle, `status`, `logs`, `doctor` | They touch only files and services `_vilice` owns. |

`prepare` creates the `_vilice` user, so it cannot run as it.

## Why `authorize`/`revoke` left the ceiling

They edit `~_vilice/.ssh/authorized_keys` — Vilice's own file. Writing your own file is
not a privileged act. No root, no `sudo`, no named-admin layer; and scoped keys land in
`_vilice`'s `authorized_keys`, not root's.

## Granting is the top of the ladder, not a wall above it

The earlier objection: "if a scoped key could run `authorize`, the gate could rebuild its
own gate." It assumes any scoped key could grant. Only a `grant`-scope key can;
`observe` and `operate` keys are pinned to their scope by the forced command. No
escalation path opens.

What must stay un-rebuildable:

- **Machine** — `prepare`/`harden`, root-only, no key reaches them. Replacing Vilice
  itself stays below Vilice.
- **Record** — the append-only floor (`chattr +a`) refuses even `_vilice`.
- **Rights ledger** — Vilice's own file, governed by the ladder.

## What a compromised account can still do

Code running as `_vilice` can edit `authorized_keys` directly, unrecorded. No scope change
fixes that, because the account owns the file. What bounds the damage is that the record
floor and the machine ceiling stay out of its reach. No *key* opens that door: no scope
grants a shell.

## Corollaries

- **Refuse bare root.** Every command except the root commands and `snapshot` refuses
  `euid 0`, with a `sudo -u _vilice …` hint.
- **`PermitRootLogin no` becomes viable.** `harden` disables root SSH only if a non-root,
  key-capable account exists (uid ≥ 1000, login shell, `authorized_keys`); otherwise it
  keeps `prohibit-password`, so a fresh box is never locked out. The root password is left
  as a console break-glass.

## Two scope axes, and `apply-updates` (2026-06-11)

- **Client scope** (`observe ⊂ operate ⊂ grant`) — what a remote caller may invoke.
- **On-box privilege** (`_vilice` ⊂ root) — what the command needs locally.

They are independent. `apply-updates` is operate-scoped and needs root for apt, so it was
refused as root and failed as non-root. **Fix:** `prepare` lays `/etc/sudoers.d/vilice`
allowing exactly `apt-get update -y` and `apt-get upgrade -y`; the command runs them with
`sudo -n`. The grant is as readable as `authorized_keys`. It was the only operate or
observe command that needed root.

## Roads not taken

- **Keep `authorize`/`revoke` root, behind a named `sudo` admin** (`SUDO_USER` recorded as
  actor). It re-imports a named-admin and sudoers layer to protect a file Vilice already
  owns; the protection is small, since a `_vilice` compromise already has code execution;
  and it keeps root in the daily loop. Kept as the fallback if granting must ever be a
  hard wall above `operate` — a multi-tenant or delegated fleet.
- **Move `apply-updates` to the root tier.** It could then not be issued over scoped SSH,
  which authenticates as `_vilice`.
