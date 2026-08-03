# Packs

> How Steward is layered: a small **core** that owns the gate, the record, and the
> ceiling, and **verb packs** it dispatches to. The *why*, and the end state this is
> heading for, is in [`decisions/core-and-packs.md`](../../decisions/core-and-packs.md).

**Status:** Canonical for what is built today — the line, the contract, one pack, the
shelf, and the manifest, all in one binary. What is **decided but not built** is the
out-of-process half: loading a pack that is a separate file, and the digest-pinned
`execveat` that would do it. Last touched 2026-08-03.

---

## The shape

```
cmd/steward/            the wiring: register the packs, hand argv to the core
internal/core/          the trust layer — dispatch, gate, record, ceiling, auth
internal/pack/app/      steward-app: the founding verb pack
```

The core never learns what a verb does. It resolves a name to a `Command`, applies the
account gate, writes the record, and calls the function. Everything a pack contributes
arrives through that one door.

## What is core, and stays core

`prepare`, `harden`, `uninstall`, `authorize`, `revoke`, `verify`, `record`, and the
`_exec` forced-command entry. These *constitute* the trust model: the ceiling that
mutates the box, the rights ledger, and the chain. They can never move to a pack,
because a trust model with a plugin interface is not one.

`apply-updates` is core today for want of a better home — it acts on the machine, not
on apps. Whether it belongs to a future `steward-machine` pack is open
([`decisions/open/steward-open-questions.md`](../../decisions/open/steward-open-questions.md)).

## The contract

A pack satisfies `core.Pack`:

- **`Name()`** — the pack's name, as it will appear in the manifest and the record.
- **`Verbs()`** — the commands it contributes. Fields are written **keyed, not
  positional**: a pack is compiled against a core it does not own, and an unkeyed
  literal would silently rebind the day `Command` grows a field.
- **`Inventory()`** — what the pack has placed on the box, by name. The ceiling needs
  the names to tell an operator what `uninstall` is about to affect, without knowing
  what any of them are.
- **`TeardownNote(w)`** — what an operator must know before the pack's things go. It
  writes where a secret lives, never the secret.

- **`Substrate()`** — what the pack needs installed, declared so the ceiling can
  aggregate it across packs and ask the operator **once**, before anything is
  installed. It carries a `Note` for what a package list cannot convey — a
  third-party apt repo, say — because that is part of what is being consented to.
- **`Prepare()`** — install and configure that substrate. Called as root after the
  accountability floor is laid, so a pack can rely on the steward account and the
  record already existing. Nothing in the floor may rely on a pack.

`Inventory` and `TeardownNote` exist because `uninstall` is a core verb that has to
describe things only a pack understands; `Substrate` and `Prepare` are the same
problem at the other end of the box's life.

**The core no longer installs or runs any of the substrate.** Podman, Caddy and restic
are `steward-app`'s dependencies — a box with no app pack needs none of them — so the
pack installs them, configures Caddy's routing, and reports its own versions. The
ceiling lays the floor and asks each pack to make itself workable.

**Known residue:** the core still *names* the substrate in prose — `uninstall` says
what it is leaving behind ("podman, caddy, restic"), and the man page describes apps as
Quadlet units behind Caddy. That is accurate for the configuration we ship and it
executes nothing, but it is the core assuming which pack is installed. Routing that
copy through the packs is unfinished business, tracked in
[`decisions/open/steward-open-questions.md`](../../decisions/open/steward-open-questions.md).

## Which code may run

Two root-owned paths, doing two different jobs:

```
/usr/libexec/steward/          the shelf — where pack binaries live
/etc/steward/packs.manifest    the manifest — which packs may run, at which digest
```

**The directory locates; the manifest authorizes.** Presence on the shelf is not
permission: a binary in the right place with the wrong hash is refused exactly as one
that isn't there. This is the digest-pinning rule Steward already applies to container
images, turned on its own extensions.

Neither path is configurable — no flag, no environment variable, no config key. A knob
that redirects discovery reintroduces everything wrong with resolving packs through
`$PATH`, through a side door. Tests reach them through an unexported package variable;
nothing else can.

The manifest is line-oriented and plain, like `authorized_keys` — `cat` it and you can
see what may run:

```
# Managed by `steward prepare`. Which packs may run on this box.
steward-app sha256:6b2f…
```

**`prepare` writes it**, naming every pack the binary carries at the binary's own
digest, creates the shelf, and **records each authorization in the chain**. So "what
code was ever allowed to run on this box, and when" is answerable from the record
alone. `uninstall` removes the manifest — withdrawing the authorization is what stops
the packs, the same way removing the ledger, not the keys, is what `revoke` does.

**The check is on the hot path.** Before any packed verb runs, the core confirms the
manifest authorizes that pack at this binary's digest. It is not a mechanism waiting to
be switched on later: a mismatch stops every verb the pack contributes, while the
core's own verbs keep working so an operator can still run `verify` and `record` and
see why. A missing manifest is a refusal, not a default-allow.

While packs are compiled in, the digest *is* the running binary's — the code that would
run is this code. When packs become separate files the digest is the pack file's and the
manifest line means the same thing, which is why digests are there now, before anything
is loaded from disk.

## Reading it back — `steward packs`

The companion to [`actors`](auth.md). That one answers *who may act on this box*; this
answers *what code may run on it*. Both are facts the box holds, and neither should be
copied into a control plane — a stored list would eventually disagree with the machine
and be believed.

`packs` joins the manifest against what the binary actually carries, and reports four
states. The three unhappy ones are why the verb exists:

| State | Meaning |
|---|---|
| `active` | authorized at this binary's digest, and carried. It runs. |
| `stale` | authorized at a *different* digest — an upgrade that skipped `prepare`. Nothing runs, and from the refusal alone this is indistinguishable from a tampered binary. |
| `missing` | authorized, but this binary does not carry it. Nothing to run. |
| `unauthorized` | carried but not in the manifest. The verbs exist and are refused at the gate. |

`unauthorized` is the one nothing else can show: that code never appears in the
manifest, so no list names it, and it never runs, so nothing fails. Problems sort
first. A read — unrecorded, no privilege.

It is also what lets a console be **pack-shaped**: a box's Apps dashboard should exist
because the box says it runs `steward-app`, not because the reader assumed it.

## Registration

`core.Register(pack)` appends a pack's verbs to the dispatch table, in registration
order. Two rules hold:

- **Registration grants nothing.** It adds names the gate will check, record, and then
  run. There is no path around any of that, and no way for a pack to add an entry
  point of its own.
- **A pack may not claim a name that is already taken.** `Lookup` returns the first
  match, so a duplicate would sit in the table unreachable while `help` and the man
  page both listed it — and nobody could say which one a scoped key had invoked. A
  verb that cannot be identified from its name cannot be accountable, so the collision
  panics at wiring time rather than being resolved by an arbitrary rule.

## How this is tested

The core's own tests register a **fake** pack, never `steward-app`. The gate, the scope
ladder, and the record-before-act rule have to hold for whatever a pack contributes —
including one written by somebody else — and testing them against the shipped verbs
would only ever prove they hold for the shipped verbs.

What only the assembled binary can prove is tested in `cmd/steward`: that the surface
we ship is the one we mean to, and that drawing the line did not drop a verb.
