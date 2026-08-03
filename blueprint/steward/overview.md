# Steward

> The entry point for the Steward spec. Plain prose here; the per-concern files
> next to it carry the detail.

**Status:** Canonical. Last touched 2026-08-02.

---

## What it is

Steward is the program on every machine. It is the layer with the privilege: it runs
apps as containers, routes traffic to them, and keeps the record of what happened. A
single static Go binary, run as **the one `steward` user** — one account per box, one
state dir, one record, and the binary refuses to act as anyone else (see
[`decisions/one-steward-per-box.md`](../../decisions/one-steward-per-box.md)).

You reach it over **scoped SSH** — a key pinned to a forced command. Day to day a
person doesn't type it; Steward Console drives it over that same channel. It is also the
breakglass tool: the operator always has it over their own SSH.

## The one claim

Everything Steward does rests on a single property:

> **Un-bypassability** — there is no path to the box's power that skips a named,
> scoped, recorded invocation.

That is the whole security claim, and it is small enough for one person to check.
Steward is where the Agora articles stop being words and become mechanism.

The claim holds **without an asterisk**, and the mechanism is that **no scope is a
shell**: every key resolves to a named command or to nothing, so there is no grant whose
holder can act on the box without an entry being written first. The top rung used to hand
out an interactive shell, and that one exception is what the claim used to be missing —
see [`no-key-gets-a-shell.md`](../../decisions/no-key-gets-a-shell.md).

## Tenets

What Steward is, one line each — with the mechanism that makes the line true, per the
Agora rule that an article without a mechanism isn't applied:

- **One door.** A single entry for hosting apps on a Linux box. The door is also the
  audit point — one door is *why* un-bypassability is checkable at all.
- **Plain speech.** It talks like a person, not a manual — admin-level precision in
  non-admin vocabulary. Mechanism: every command carries its own help page, and every
  usage error carries the synopsis (they are the same string in `internal/core/dispatch.go`, so they
  can't drift).
- **Standard tools, standard idiom.** It relies on Podman, Caddy, OpenSSH, and systemd
  *on purpose* ([`decisions/borrowed-substrate.md`](../../decisions/borrowed-substrate.md))
  and drives them in their native config — never a fork, never a private format.
  Everything it writes is the tool's own plain file, readable by an admin who has
  never heard of Steward.
- **A gate and a scribe, not a runtime.** No daemon, no listener, no token; it exists
  only while a command runs. Delete the binary and nothing running stops — apps are
  ordinary Quadlet units under systemd, routes are plain Caddy config. What stops is
  the gate and the record.
- **One steward per box.** One named account, one state dir, one record — enforced by
  the binary, not the README
  ([`decisions/one-steward-per-box.md`](../../decisions/one-steward-per-box.md)).
- **If it can't write the record, it doesn't act.** `dispatch` writes the entry before
  the action runs (invariant 2, in `internal/core/dispatch.go`).
- **Fail loud, never silent.** An unknown flag is refused, the wrong user is refused,
  a failed pull is classified — a quiet wrong outcome is worse than a loud stop.
- **Breakglass is the tool itself.** Recovery is Steward over the operator's own SSH,
  never the web UI.
- **Open.** AGPL, auditable, one person can hold it in their head
  ([`decisions/licensing.md`](../../decisions/licensing.md)).

## Core and packs

Steward is two layers in one binary. The **core** owns the gate, the record, and the
ceiling; **verb packs** own what a verb actually does. The core resolves a name,
applies the account gate, writes the record, and calls the function — it never learns
what the function does. `steward-app` is the founding pack and holds deploy, lifecycle,
backup, and the observe verbs.

The layer that must be trusted is therefore the core plus the packs' names and
digests, not the whole binary — which is the point, since the core can be finished
while verbs keep changing. See **[packs.md](packs.md)** for the contract and
[`decisions/core-and-packs.md`](../../decisions/core-and-packs.md) for the why.

## The four concerns

Each is one spec, and each is one surface to audit on its own:

- **[provision.md](provision.md)** — get the box ready (`harden`, `prepare`). Lays
  the floor the rest stands on. Core.
- **[auth.md](auth.md)** — who may act, at what scope (scoped SSH). Invariant 1. Core.
- **[record.md](record.md)** — what happened, kept honest. Invariant 2. Core.
- **[deploy.md](deploy.md)** — put apps on the box and run their lifecycle. Wide,
  not deep. This one is a **pack**, not core.

## The legible ceiling

Three commands are **root-only** and reachable by no scoped key: `harden`, `prepare`,
and `uninstall`. They change the box itself, so a scoped key must never reach them —
the gate cannot rebuild (or remove) its own gate. This is invariant 3, enforced by filesystem ownership. Every other
command, including `authorize`/`revoke`, runs as the unprivileged `steward` user:
granting and revoking are the **top rung of the scope ladder** (`grant` scope), not a root
wall above it — the ceiling is the machine and the record, not the rights ledger. Named
in [provision.md](provision.md) and [auth.md](auth.md); the why is in
[`decisions/ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).

## Command reference

The user-facing command list lives in [`site/content/index.md`](../../site/content/index.md);
the pack surface is in [`site/content/packs.md`](../../site/content/packs.md).
The specs here say how each command behaves and which article it encodes.

The CLI's own help is part of the contract: `steward help <command>` (or `--help` on
any command) prints the command's page — summary, synopsis, and **which scope may run
it**, making help a second view of the rights ladder. A flag a command doesn't declare
is a hard error carrying the synopsis, never silently dropped; `--help` never falls
through to the action it asks about.

The man page is the same table's third view: `steward _man` generates `steward.1`
from the commands table (`make man`; shipped in the release tarball, installed by
`install.sh`), so help, usage errors, and `man steward` cannot drift apart.

## Open questions

What is not yet decided is kept out of this folder, in
[`decisions/open/steward-open-questions.md`](../../decisions/open/steward-open-questions.md).
When a question settles, its answer moves into the spec here and its reasoning into
`decisions/`.
