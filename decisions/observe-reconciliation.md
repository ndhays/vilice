# An observe read reconciles the stored projection

> Decided 2026-06-17. Refines [two-records.md](two-records.md).

## The problem

`Vilice::Observe` read a box's `status --json` and cached it, and did nothing else. The
columns meant to mirror the box — `machine.status`, `machine.last_seen_at`,
`placement.current_image` — were never written by the read path. The Status page, the
`drift` rollup and the unreachable signal all read inputs nothing updated.

## The decision

**Every real observe read reconciles the stored projection, inline.**

On success: `machine.status = reachable`, `machine.last_seen_at = now`, and each reported
app's live `Placement` gets its `current_image`.

On failure: `machine.status = unreachable`. `last_seen_at` is left alone — it means the
last time the box answered.

It runs on a **cache miss only**, so it fires when the box was actually reached. Writes
use `update_columns`: no callbacks, no `updated_at`, and **no `Event`**.

## Why this is not a second recorder

Vilice is the sole recorder of the box. Reconciliation writes the console's own mirror of
reachability and the running image — the mirror the cache already was, persisted. No box
entry is authored and no console `Event` is written, because nothing on the box changed.
A normal save would imply an act worth a timestamp; a projection is not one. Witnessed
acts still go through the ceremony.

## Why on read, not a separate ingester

The read already has the data parsed, so the projection is right the moment any surface
reads a box, with no second path to drift from the cache. Fleet-wide freshness is the
same read on a schedule (`FleetObserveJob`).

## Roads not taken

- **A separate `Snapshot` table as the source of truth.** Splits "what the box said"
  across two stores. A queryable history is still wanted for forensics, as an addition.
- **Marking the placement `failed` on a failed deploy.** A failed pull leaves the running
  app untouched, so the truth is "still on the old image". A real `failed` needs per-app
  container state from the box — open in
  [open/status-signals.md](open/status-signals.md).
- **An `Event` per read.** Floods the record with non-acts.
