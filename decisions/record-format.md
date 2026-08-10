# The record format is locked: own-file JSONL + sha256 hash chain

**Decided 2026-06-09.** Settles the "tamper-evidence — journald FSS vs a hand-rolled hash
chain" open question. The canonical format is specified in
[`blueprint/steward/record.md`](../blueprint/steward/record.md); this records the *why*
and the road not taken.

## What's locked

The record is a standalone append-only file (`/var/lib/steward/record.log`, `chattr +a`
set by `prepare`), one JSON entry per line. Each entry carries `seq`, `time`, `actor`,
`scope`, `action`, `args`, `prev_hash`, and `hash`, where `hash = sha256(canonical JSON
of every field except hash)` and `prev_hash` links the entry before it. `steward verify`
(observe scope) walks the chain and reports the first break — a reorder, a broken link, or
an edited entry — or confirms it intact. This is the 1.0 contract: an outside party can
verify a chain from the spec alone, without reading the Go.

## Why not journald Forward Secure Sealing (FSS)

FSS was the tempting alternative — tamper-evidence for one `journalctl` flag instead of
our own code. We declined it, because it is **not a swap of the tamper-evidence
mechanism — it is a change of substrate.** Using FSS means putting the record *into
journald*, and that fights two commitments already made:

- **Off-host shipping** (the remaining record open question): a line-oriented JSONL file
  ships off the box trivially — append, tail, copy. A sealed journal does not.
- **"The record outlives the box"** (`record.md`): journald is entangled with the host
  we are trying to outlive. Owning the file keeps the record portable and independent of
  the host's logging stack.

So owning the file plus a sha256 chain is the substrate that *enables* the off-host
fast-follow, not just the one that happened to be built. FSS would have coupled the record
to the host at exactly the layer where independence matters most.

## A bug this surfaced (worth recording)

Exposing `verify` as a command immediately caught a latent chain bug: a no-arg command
(`prepare`, `harden`, `apply-updates`) reaches `record()` with an *empty but non-nil*
arg slice, which hashed as `[]` at write time — but `omitempty` dropped the field on
disk, so it reloaded as `nil` and hashed as `null` on verify. Every no-arg entry broke
its own chain, and those are the *first* entries on a real box. `computeHash` now
normalizes an empty arg list to nil so absent/empty/nil all hash identically; a
regression test (`TestVerifyChainEmptyArgsHashStable`) pins the real dispatch path
(`filtered[1:]`), which the prior tests missed by only ever passing `nil`. The lesson:
a tamper-evidence claim is only real once something *runs the check* — which is the whole
case for shipping `verify` in 1.0.

## The schema grows additively, or not at all

Added 2026-08-03, when `pack` and `digest` joined the entry
([`core-and-packs.md`](core-and-packs.md)).

> **Still the rule, 2026-08-10.** `pack` is retired — the layer that wrote it is gone
> ([`roles-not-packs.md`](roles-not-packs.md)) — but the field stays in the wider
> payload and nothing sets it. Removing it from the hash would have been the same
> mistake in reverse: every entry on every box that carries one would report a break.
> **A field can stop being written; it cannot stop being hashed.**

The hash covers every field, and `verify` recomputes it. So a field added to the
payload for *all* entries changes the hash of every entry ever written, and the first
thing an upgraded binary does is report that the chain broke at entry 1 — the record
accusing itself of tampering because the software changed. On an append-only file
(`chattr +a`) there is no rewriting your way out of that.

The rule: **an entry that does not carry the new field hashes exactly as it always
did.** Only an entry that carries it commits to the wider payload. Two shapes, chosen
on whether the field is present.

The cost, stated plainly: an entry with no `pack` is indistinguishable from one whose
`pack` was stripped, because both hash under the narrow shape. That is inside root's
existing power — root can already rewrite the whole chain and recompute it — and the
chain's guarantee was always tamper-*evidence* against everything short of root, which
cannot write the file at all. It is not a new hole, but it is the price of being able
to read your own history, and it is worth knowing rather than discovering.

`digest_test.go` pins a hash for each shape. Changing either breaks a test loudly,
which is the only warning anyone gets before shipping a version that cannot verify its
own past.

## Roads not taken

- **journald FSS** — substrate change, fights off-host shipping and box-independence
  (above).
- **Inlining a signature per entry** instead of a chain — heavier, and the chain plus an
  off-host copy already gives "edits show." Per-entry signing only matters if the signing
  key lives off the box, which is the god-key-custody work, tracked separately.
