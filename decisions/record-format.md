# The record format is locked: own-file JSONL + sha256 hash chain

> Decided 2026-06-09. Spec: [`blueprint/vilice/record.md`](../blueprint/vilice/record.md).

## What is locked

The record is an append-only file (`/var/lib/vilice/record.log`, `chattr +a` set by
`prepare`), one JSON entry per line. Each entry carries `seq`, `time`, `actor`, `scope`,
`action`, `args`, `prev_hash`, and `hash`, where `hash = sha256(canonical JSON of every
field except hash)`. `vilice verify` (observe scope) walks the chain and reports the first
break. An outside party can verify a chain from the spec alone.

## Road not taken: journald Forward Secure Sealing

FSS is tamper-evidence for one `journalctl` flag. But it is a change of substrate — the
record would live in journald:

- **Off-host shipping.** A JSONL file ships by append, tail, copy. A sealed journal does
  not.
- **The record outlives the box.** journald belongs to the host the record is meant to
  outlive.

## Road not taken: a signature per entry

Heavier, and the chain plus an off-host copy already shows edits. Per-entry signing only
matters if the signing key lives off the box.

## The schema grows additively, or not at all

The hash covers every field. A field added to all entries changes every hash ever
written, and an upgraded binary reports the chain broken at entry 1. On an append-only
file there is no rewriting out of that.

**The rule: an entry that does not carry the new field hashes exactly as it always did.**
Only an entry that carries it commits to the wider payload.

The same rule runs in reverse. `pack` is retired ([`roles-not-packs.md`](roles-not-packs.md))
but stays in the wider payload, unset. **A field can stop being written; it cannot stop
being hashed.**

The cost: an entry with no `pack` is indistinguishable from one whose `pack` was stripped.
That is inside root's existing power — root can rewrite and recompute the whole chain —
and the chain was always evidence against everything short of root. Not a new hole.

`digest_test.go` pins a hash for each shape.

## A bug `verify` caught

A no-arg command reached `record()` with an empty, non-nil arg slice. It hashed as `[]` at
write time, `omitempty` dropped it on disk, and it reloaded as `nil` and hashed as `null`.
Every no-arg entry broke its own chain — and those are the first entries on a real box.
`computeHash` now normalizes an empty list to nil
(`TestVerifyChainEmptyArgsHashStable`). A tamper-evidence claim is real only once
something runs the check.
