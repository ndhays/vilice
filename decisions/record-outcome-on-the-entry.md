# An act's outcome settles on its own entry

> Decided 2026-06-11. Refines [two-records.md](two-records.md).

## The problem

An act is recorded before it runs, so the entry is written without knowing the result.
But `Event` is append-only by mechanism: a `before_update` hook raises on any edit.
Stamping "succeeded" on the entry is an UPDATE.

## The decision

**The outcome lives on the same entry and settles exactly once.**

`Event` has `outcome` (nil → "pending" → "ok"/"failed"), `finished_at`, and `detail`.

- The recorded **facts** (`actor`, `action`, `at`, the subject, `summary`, `raw`) stay
  frozen; changing one still raises.
- The **outcome** may move once, from `pending`, through `Event#settle!`. A second settle
  raises. The guard checks the changed columns are within `Event::SETTLE_COLUMNS` and
  `outcome_was == "pending"`.
- An instantaneous act (a label edit) passes no outcome and never settles.

## Why

- **One entry per act.** The timeline shows *deploy acme-web* going from running to
  succeeded in place.
- **A pending row that never settles is evidence.** If the box vanishes between the
  record and the reply, the entry says "we issued this and never learned the result".
- **It does not weaken the record.** The guard exists to stop rewriting and deletion. An
  outcome is new knowledge, and it moves one way, once. The console's record was never
  hash-chained; the box's chain is the anchor.

## Road not taken

**A follow-up entry** for the outcome. Leaves the guard untouched, but doubles the
timeline and needs intent-to-outcome correlation. If strictly immutable rows are ever
required, the outcome could move to a child record.
