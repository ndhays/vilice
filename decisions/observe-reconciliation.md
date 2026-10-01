# An observe read reconciles the stored projection

> Refines the two-records model in [two-records.md](two-records.md) and the live-status
> machinery noted built there. Settled 2026-06-17 while closing the Status-page signal
> gaps ([open/status-signals.md](open/status-signals.md)).

## The question

`Steward::Observe` reads a box's live `status --json` over scoped SSH and **caches** the
reply (Decision 3). The cache made reads cheap — but it was *all* the read did. The
persisted columns that exist precisely to project box truth into the control plane —
`machine.status` (the `unknown`/`reachable`/`unreachable` enum), `machine.last_seen_at`,
and `install_target.current_image` — were **never written by the read path**. They were
declared and then only ever set at deploy time (`desired_image`) or not at all.

So the Status page, the install `drift` rollup, and the unreachable-machine signal were
reading a projection that nothing updated: `machine.status` sat at `unknown` forever and
`current_image` stayed nil. The page was correct; the inputs were dead.

## The decision

**Every real observe read reconciles the stored projection, inline in the read path.**

On a successful `status` read:

- `machine.status = reachable`, `machine.last_seen_at = now`.
- For each app the box reports (`data.apps[] = { name, image }`), the live
  `InstallTarget` for that install on that machine gets its `current_image` set — the
  exact input `in_sync?`/`drift` needs.

On a failed read: `machine.status = unreachable`. `last_seen_at` is **left alone** — it
means "the last time we actually heard from it," so a failed read must not move it.

Reconciliation runs on a **cache miss only** (it lives inside the cache-fill block), so
it fires when we genuinely talked to the box, not on every cache hit. Writes use
`update_columns`: this is a **projection, not a witnessed act** — no callbacks, no
`updated_at` churn, and crucially **no `Event`**.

## Why this doesn't add a second recorder

Two-records is the load-bearing invariant here: Steward is the *sole recorder* of the
box; Steward Console never authors the box's record. Reconciliation respects that — it writes
**Steward Console's own mirror** of reachability and the running image, the same mirror the
cached read already was, just persisted instead of thrown away. No box entry is authored;
no Steward Console `Event` is written. An observe read stays zero-privilege and accountable-to-
no-one because it changes nothing *on the box* — updating our local picture of the box is
what "mirror" already meant.

This is also why it's `update_columns`, not a normal save: a save would imply a
control-plane act worth a timestamp and (eventually) a record line. A projection is
neither. The witnessed side (deploy/rollback/remove) still goes through the ceremony and
writes an `Event`; the two sides stay cleanly apart, as
[the spine](../blueprint/console/interface.md) requires.

## Why reconcile-on-read, not a standalone ingester

The read already happens and already has the data parsed; reconciling in place means the
projection is correct the moment any surface reads a box, with no second code path to
drift from the cache. The **fleet-wide freshness** problem — keeping the Status page true
for a box nobody has opened — is solved by *scheduling* the same read (`FleetObserveJob`
sweeps the fleet on a cadence), not by a separate ingestion pipeline. One read path, used
on demand and on a timer.

## Roads not taken

- **A separate `Snapshot`/ingestion table as the source of truth.** Heavier, and it
  splits "what the box said" across two stores (the cache and the table). The columns
  already model the projection; persisting into them keeps one shape. The cross-fleet,
  queryable `Snapshot` history is still a real future item, but it's an *addition* for
  forensics, not the path that lights up the Status page.
- **Marking the target `failed` on a failed deploy.** Per
  [deploy.md](../blueprint/vilice/deploy.md) a failed pull leaves the running app
  untouched, so the truthful state is "still on the old image," not "dead." A genuine
  `failed` needs the box to report per-app container state, which `status --json` doesn't
  carry yet — left open in [open/status-signals.md](open/status-signals.md).
- **Writing through `update`/an `Event` per read.** Would imply each read is an act and
  flood the record with non-acts. Rejected; a projection is not a witnessed change.
