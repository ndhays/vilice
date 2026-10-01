# Scenario seeds, and faking health without a box

Vilice Console's dev seeds are a set of named scenarios — `empty` (the default),
`realistic`, `all_clear`, `all_broken`, `big_fleet` — selectable by `SCENARIO=` /
`bin/scenario` (see `console/db/seeds/README.md`). The point is a one-command,
deterministic world for demos, manual walk-throughs, accessibility passes, and
integration audits.

The one real design choice was **how to render machine health with no box.**

Health (online/offline, load, memory, disk, hardening) is not stored — it's read
live from `vilice status --json` over scoped SSH and cached briefly
(`Vilice::Observe`, decisions/two-records.md). So a scenario that wants a
"critical" or "offline" box has nothing in the database to set; without a real
host every box just reads unreachable.

## Chosen: a dev-only fake-observe seam

`Vilice.read` short-circuits to `Vilice::Fake.envelope` when
`VILICE_FAKE_OBSERVE=1` **and** the env is dev/test, returning a canned reply
built from each machine's `fake-health` label. It can never act in production (the
`Rails.env.local?` half of the guard), and it sits at the single transport
chokepoint the test fake already proved out (`test/test_helpers/fake_vilice.rb`),
so the real `Vilice.read` JSON/error handling is untouched.

Why this and not the alternatives:

- **Prime the observe cache (rejected).** Seeds could write fabricated envelopes
  straight into solid_cache. No app-code change — but the 30s TTL expires and the
  next page falls back to "can't reach this box." Scenarios that don't hold still
  are useless for a walk-through or an a11y crawl. Determinism across every request
  is the whole value, so the small, gated seam earns its place.
- **Real loopback Vilice (rejected for this).** The dev harness can run a real
  local `vilice` over loopback SSH, but it can't fabricate offline/critical boxes,
  needs keys per box, and the dev sandbox blocks loopback TCP except :22. Good for
  proving the live round trip; wrong tool for scripted scenario states.

## Notes

- Health is label-driven (`fake-health: ok|warn|crit|offline`); `crit` also shows
  hardening drift. Everything else a scenario shows (event outcomes, install drift,
  `last_seen`, list size, empty states) is ordinary seeded DB state — the seam only
  covers the live-read half.
- The default is `empty` (an operator and nothing else), so plain `bin/rails db:seed`
  and `db:reset` give a clean slate you can still sign into; `realistic` is the
  opt-in dev-data world. Every scenario but `realistic` wipes domain data first
  (keeping users) because they are contradictory worlds — and the wipe is a no-op
  outside dev/test, so a stray seed can never clear a production database.
- This is dev/test tooling, so it lives in code + `db/seeds/README.md`, not in the
  `blueprint/` (which describes the running system, not its fixtures).
