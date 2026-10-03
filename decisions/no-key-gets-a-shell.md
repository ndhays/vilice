# No key gets a shell

> Decided 2026-08-02. The top rung of the scope ladder is renamed `ssh` → **`grant`**
> and loses the interactive shell it used to carry. Every key now resolves to a *named
> command* or to nothing. Mechanism: `decideExec` refuses an empty command at every
> scope, `execShell` is deleted, and `forcedLine` writes plain `restrict` with no
> exception.
>
> Reverses an earlier acceptance of that cost in
> [ceiling-is-the-machine.md](ceiling-is-the-machine.md).

## The bite

`ssh` scope bundled two unrelated things:

1. **The rung that mints keys** — the only scope that can run `authorize`/`revoke`.
2. **An interactive shell as the `_vilice` user** — an empty `SSH_ORIGINAL_COMMAND` was
   turned into `execShell()`, and the key's `authorized_keys` line carried
   `restrict,pty` instead of plain `restrict`.

The second breaks the one claim. [overview.md](../blueprint/vilice/overview.md) says
un-bypassability means "there is no path to the box's power that skips a named, scoped,
recorded invocation." A shell as `_vilice` is exactly that path. From it you can
`podman run` directly, hand-write a Quadlet unit and `systemctl --user start` it, and
rewrite `/etc/caddy/vilice/apps.caddy` (the `_vilice` user owns it) then reload Caddy
through its admin API on localhost. None of that writes a record entry. The record shows
one `action="shell"` line and then nothing.

So for that one key, invariant 2 degraded from *every action is recorded before it runs*
to *we know a shell was opened at 14:32*.

`ceiling-is-the-machine.md` saw part of this and accepted it, but framed the cost
narrowly — as "can edit `authorized_keys` out of band" — and reasoned that such an actor
"already has arbitrary code as `_vilice`," so key persistence was marginal. That reasoning
is sound about *persistence* and misses the bigger point: the unrecorded surface isn't
just the ledger, it's every action the box can take. The asterisk wasn't on Article IV,
it was on the headline claim.

## The decision

**Unbundle them. Keep the rung, delete the shell.**

- `grant` scope mints and revokes keys. That is all it does.
- No scope produces a shell. An empty command is refused at every rung — and the refusal
  is itself recorded as a denial, so even the attempt is accountable.
- `restrict` on every line, no `pty` exception anywhere.

The result is that un-bypassability holds without qualification: **there is no grant
Vilice can issue that lets its holder act on the box without an entry being written
first.** That is a stronger claim than the project could make yesterday, and it is the
kind of claim that is worth more than the convenience it costs.

A second-order gain: because `grant` no longer implies a shell, it is narrow enough to
*issue*. A control plane can hold one and enroll keys without also holding the box —
which is why Vilice Console's `Machine` scope enum gains `grant` alongside observe/operate.
Under the old design that was unthinkable, and the enum said so by omitting `ssh`.

## What it costs

The ability to get a shell **as `_vilice`** using a **vilice-scoped key**. Two things
that look like losses are not:

- **Breakglass is untouched.** It was never the scoped key. `overview.md` says recovery
  is "Vilice over the operator's own SSH" — the operator's own account, then
  `sudo -u _vilice vilice …`. `harden` guarantees such an account exists: it only closes
  root SSH when a non-root keyed admin is already present, and never leaves a box with no
  key-based login at all.
- **The `_vilice` account keeps `/bin/bash`.** It must — sshd runs forced commands
  through the login shell, which is why `ensureViliceUser` refuses `nologin`. What went
  away is the `pty` option and the empty-command path, not the shell binary.

The real cost is the escape hatch. `ssh` scope was how you did something Vilice has no
command for. Now either the command surface is good enough, or you use your own account.
We take that trade deliberately: it is pressure in the direction the design already
wants — every operation becomes a named, recorded command — and where it can't, your own
account is a *different named actor* with its own sshd and sudo trail, rather than an
anonymous session wearing the `vilice` identity.

## What it does not fix

This does not stop a `vilice`-user **compromise**. Anyone with code execution as
`vilice` by some other route still bypasses everything, and the original decision was
right about that. What changes is that we stop *handing that capability out as a routine
grant*: it moves from "a scope you can issue" to "a breach you would investigate." A
meaningfully smaller blast radius, not a new kernel boundary — and worth saying plainly
rather than overselling.

## Migration

Keys authorized before the rename carry `--scope ssh` in their forced command.
`normalizeScope` reads that as `grant`, so they keep working — they simply no longer get
the shell the name promised, and an attempt to open one is denied and recorded. The name
is also still accepted on input, so the documented onboarding line and any runbook that
predates this keep working; `authorize` writes `grant` either way, so the ledger converges
as clients are re-authorized. No flag day, and no key silently gains or keeps a capability.

## Roads not taken

- **Keep the shell, record more of it.** Log the session, or wrap it. Session recording
  is a large, defeatable mechanism (the shell can spawn anything), and "recorded" would
  still mean "a transcript exists," not "the action was authorized and chained." It buys
  forensics where the design asks for a gate.
- **Keep `ssh` as a fourth, rarely-granted scope.** The capability is the grant, not the
  usage — a scope nobody is supposed to use is one that eventually gets used, and its
  existence is what puts the asterisk on the claim. Deleting it is the only version that
  makes the claim true.
- **Also remove the rung** (make `authorize`/`revoke` on-box-only, human-only). Tempting,
  and genuinely simpler. Rejected because the first key on a box is already human-placed
  by necessity — the chicken-and-egg in
  [machine-onboarding.md](machine-onboarding.md) — and making *every subsequent* grant a
  human-at-the-box event removes remote enrollment for no security gain, now that the rung
  is not a shell.
- **Rename to `admit`, or `keys`.** `grant` is what the docs already called the act
  ("Granting is the top rung of the ladder"), so the name was chosen for us.

## What this answers preemptively

"Can a Vilice key ever give me a shell on the box?" — No. Not at any scope, not with any
argument. If you need a shell, you need an account, and that is a different named actor
with its own trail. That is the whole point.
