# Two records — the box's and the control plane's

> Decided 2026-06-10.

## The decision

There are two records, by layer. Neither contains the other.

- **Vilice's record** — the box's. What touched this machine's power. Hash-chained,
  append-only (`chattr +a`), per machine. Authoritative for what happened to the box.
- **The console's record** — the control plane's. What operators did in the fleet UI.
  Authoritative for what happened there. **Not hash-chained.**

"Vilice is the sole recorder" is true for the box. Invariant 2 applies to the console at
its own layer.

## What only the console can record

1. **Acts with no box involved** — created a project, linked a machine, rotated a stored
   key, added a label.
2. **The human.** Vilice records the key's client name (`client=console`); only the
   console knows the person behind it.
3. **Fleet-level grouping.** "Deploy to A and B" is one act; each box records its half.
4. **Intent and outcome at the edge.** A refused or failed command may never reach the
   box, but the attempt is what accountability wants.
5. **Reads worth tracking** — exports and sensitive reads do not touch the box.
6. **The console's own security** — logins, sessions, grants, connecting a machine.

## Mirror is not record

For everything that did touch a box, the console mirrors Vilice's record for display and
search. The mirror is a cache: re-pull and it rebuilds. So `Event` holds two things that
must not be mixed:

- **The console's own acts** — authoritative, not re-derivable.
- **A mirror of the box's record** — a read cache.

The displayed chain is a merge of the two. That is also where *authored* (the console ran
it) versus *witnessed* (it appeared in the box record from elsewhere) comes from — by
layer, not by string matching.

## Why the console's record is not hash-chained

A hash chain earns its cost only at an un-bypassable privilege boundary with an anchor
outside the attacker's reach. Vilice has both. That matters for the cases that worry us —
two consoles driving one box, or an admin acting by hand — because every such path still
goes through Vilice's gate.

A chain stored in the database it protects is theater: anyone who can write the rows can
recompute it. And the box record already is the external anchor — anything that touched a
box is in a chain the console does not control, so the console's account can be
cross-checked.

Rails has no native pattern for it either: `audited` and `paper_trail` are versioning,
`ActiveRecord::Encryption` is confidentiality.

**Instead:** append-only by mechanism (no edit or delete paths; the outcome settles once
— [record-outcome-on-the-entry.md](record-outcome-on-the-entry.md)), record-before-act
with the human named, ordinary DB integrity and backups, and cross-checking against the
box.

**Road not taken: external anchoring** — ship digests to an append-only store or SIEM.
The move if a compliance case ever demands tamper-evidence for console-only acts.

## Still open

Whether `Event` becomes Boxcar `Eventable`, and the persisted mirror — ingestion, #6 in
[`open/ui-roadmap.md`](open/ui-roadmap.md).
