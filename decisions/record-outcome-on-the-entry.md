# An act's outcome settles on its own entry

> Refines the append-only model in [two-records.md](two-records.md). Settled
> 2026-06-11 while building the mutate ceremony (Wave 3, Slice 1).

## The question

A witnessed act (deploy, restart, apply-updates) is recorded **before** it runs —
that's Invariant 2, record-before-act. So at write time we don't yet know whether
it worked; the line is born *running*. When the command returns we learn
*succeeded* or *failed*. Where does that outcome go?

This collides with `Event` being **append-only by mechanism**: a `before_update`
hook *raises* on any edit, a `before_destroy` on any delete. Stamping "succeeded"
onto the line written 30 seconds ago is, mechanically, an UPDATE.

## The decision

**The outcome lives on the same entry, and settles exactly once.**

`Event` gained `outcome` (nil → "pending" → "ok"/"failed"), `finished_at`, and
`detail`. The append-only guard is refined, not removed:

- The recorded **facts** (`actor`, `action`, `at`, `machine`/`install`/`project`,
  `summary`, `raw`) remain frozen forever — any attempt to change one still raises.
- The **outcome** may transition **once**, from `pending` to a settled value, via
  `Event#settle!`. A second settle raises. (`Event::SETTLE_COLUMNS` is the allowed
  set; the guard checks the changed columns are a subset *and* `outcome_was ==
  "pending"`.)
- An instantaneous act (a label edit, a star) passes no outcome — it stays `nil`
  and never settles, so it remains fully append-only with no exception.

## Why same-entry, not a follow-up row

- **One vertebra per act.** "State is the head of the record" stays legible; the
  timeline shows *deploy acme-web* going from running → succeeded in place, not as
  two correlated lines.
- **It matches the ceremony spec** (`decisions/open/ui-roadmap.md`): "the outcome is
  stamped on the same entry."
- **A pending row that never settles is a feature.** If the box vanishes or the
  process dies between record-before-act and the reply, the entry stays `pending` —
  honest evidence that "we issued this and never learned the result," rather than a
  silent gap or a misleading success.

## Why this doesn't weaken the record

The append-only guard's purpose is *no rewriting of what happened and no deletion*.
An outcome is **new knowledge appended to a row**, not a rewrite of a recorded fact —
and it can only ever move pending → settled, once. Vilice Console's record was never
hash-chained anyway (the box's chain is the external anchor, see
[two-records.md](two-records.md)); the same-DB guard is hygiene, and this refinement
keeps that hygiene exact while letting record-before-act tell the truth about
results.

## Road not taken

A **follow-up entry** (write the intent, then append a separate "…succeeded" row)
keeps the guard untouched, but doubles the timeline, needs intent↔outcome
correlation, and diverges from the "same entry" spec. If a hard requirement ever
demands strictly-immutable rows, the outcome could move to a child record — noted,
not taken.
