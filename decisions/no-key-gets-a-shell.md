# No key gets a shell

> Decided 2026-08-02. Reverses a cost accepted in
> [ceiling-is-the-machine.md](ceiling-is-the-machine.md). Mechanism: `decideExec` refuses
> an empty command at every scope, `execShell` is deleted, and `forcedLine` writes plain
> `restrict`.

## The problem

The top scope, then named `ssh`, bundled two things:

1. **The rung that mints keys** — the only scope that can run `authorize`/`revoke`.
2. **An interactive shell as `_vilice`** — an empty `SSH_ORIGINAL_COMMAND` became
   `execShell()`, and the key's line carried `restrict,pty`.

The second breaks the claim that no path to the box's power skips a named, scoped,
recorded invocation. From that shell you can `podman run`, hand-write a Quadlet unit and
start it, or rewrite Vilice's Caddy fragment and reload Caddy. None writes a record
entry. The record shows one `action="shell"` line and then nothing.

The earlier decision framed the cost as "can edit `authorized_keys` out of band". The
unrecorded surface was every action the box can take.

## The decision

**Keep the rung, delete the shell.**

- `grant` mints and revokes keys. That is all it does.
- No scope produces a shell. An empty command is refused at every rung, and the refusal
  is recorded as a denial.
- `restrict` on every line, no `pty` exception.

**There is no grant Vilice can issue that lets its holder act on the box without an entry
being written first.**

Because `grant` is no longer a shell, it is narrow enough to issue: a control plane can
hold one and enroll keys without holding the box. The console's `Machine` scope enum
gained `grant` for that reason.

## What it costs

A shell as `_vilice` from a Vilice key — the escape hatch for anything Vilice has no
command for. Now the command surface is good enough or you use your own account, which is
a different named actor with its own sshd and sudo trail.

Two things are not lost:

- **Break-glass.** Recovery was always the operator's own account, then
  `sudo -u _vilice vilice …`. `harden` never leaves a box with no key-based login.
- **The `_vilice` account keeps `/bin/bash`.** sshd runs forced commands through the
  login shell, so `ensureViliceUser` refuses `nologin`. What went is the `pty` option and
  the empty-command path.

## What it does not fix

A compromise of the `_vilice` account by another route still bypasses everything. What
changes is that the capability is no longer handed out as a routine grant: it moves from
"a scope you can issue" to "a breach you would investigate". A smaller blast radius, not
a kernel boundary.

## Migration

Keys authorized earlier carry `--scope ssh`. `normalizeScope` reads that as `grant`, so
they keep working without the shell; an attempt to open one is denied and recorded.
`--scope ssh` is still accepted on input and written as `grant`, so the ledger converges
as clients are re-authorized. No key gains or keeps a capability silently.

## Roads not taken

- **Keep the shell, record the session.** Session recording is large and defeatable (the
  shell can spawn anything), and a transcript is forensics, not a gate.
- **Keep `ssh` as a fourth, rarely granted scope.** A scope nobody is supposed to use
  eventually gets used, and its existence is what qualifies the claim.
- **Also remove the rung** (granting only by a human at the box). Simpler. Rejected
  because the first key is already human-placed
  ([machine-onboarding.md](machine-onboarding.md)), and making every later grant a
  human-at-the-box event removes remote enrollment for no security gain.
- **Name it `admit` or `keys`.** The docs already called the act granting.
