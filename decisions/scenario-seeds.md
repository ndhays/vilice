# Scenario seeds, and faking health without a box

> Dev and test tooling, so it lives in code and `console/db/seeds/README.md`, not the
> blueprint.

The console's dev seeds are named scenarios — `empty` (default), `realistic`,
`all_clear`, `all_broken`, `big_fleet` — chosen by `SCENARIO=` / `bin/scenario`.

The design choice was how to show machine health with no box. Health is not stored; it is
read live from `vilice status --json` and cached briefly. A scenario that wants a
"critical" box has nothing in the database to set.

## The decision: a dev-only fake-observe seam

`Vilice.read` returns `Vilice::Fake.envelope` when `VILICE_FAKE_OBSERVE=1` **and**
`Rails.env.local?`. The reply is built from each machine's `fake-health` label
(`ok|warn|crit|offline`; `crit` also shows hardening drift). It cannot act in production,
and it sits at the one transport chokepoint, so the real JSON and error handling are
untouched.

Every scenario but `realistic` wipes domain data first (keeping users). The wipe is a
no-op outside dev/test.

## Roads not taken

- **Prime the observe cache** from the seeds. The 30s TTL expires and the next page reads
  "can't reach this box". A scenario that does not hold still is no use for a
  walk-through.
- **A real loopback Vilice.** Cannot fabricate offline or critical boxes and needs keys
  per box. Right for proving the live round trip, wrong for scripted states.
