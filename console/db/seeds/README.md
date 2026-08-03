# Scenario seeds

Load a whole, self-consistent world with one command — for demos, manual
walk-throughs, accessibility passes, and integration audits.

```bash
bin/scenario --list             # the scenarios
bin/scenario all_broken         # load one
bin/scenario all_clear --serve  # load it, then boot the server with live health
```

Or directly:

```bash
SCENARIO=all_broken bin/rails db:seed
rake console:scenario[all_broken]
```

## The scenarios

| Scenario     | What it shows |
|--------------|---------------|
| `empty`      | **The default.** Just an operator to sign in as — every list falls to its empty state. Plain `bin/rails db:seed` and `bin/rails db:reset` land here. |
| `realistic`  | The dev box, the loopback box (if its key exists), a couple of projects, a little activity. Additive/idempotent. |
| `all_clear`  | A healthy fleet: every box reachable and calm, apps in sync, recent acts settled ok, records intact, boxes hardened. |
| `all_broken` | Every failure mode: a box gone, one critical (with hardening drift), one under pressure; drifted and failed installs; a failed deploy and one still pending; stale `last_seen`. |
| `big_fleet`  | 8 projects × 6 machines + 200 events, health spread across the bands — for list search/sort/pagination and dense-table accessibility. |

`realistic` is additive (it never wipes). Every other scenario — `empty` included —
**wipes domain data first** (projects, machines, installs, events, labels, apps,
settings); users and sessions are kept. So loading any scenario gives you exactly
that world. (The wipe is a no-op outside dev/test, so a stray `db:seed` can never
clear a production database.)

## How health works without a box

Machine health (online/offline, load, memory, disk, hardening) is **not stored** —
it's read live from `steward status --json` over scoped SSH. To make scenarios
render deterministically with no real box, a dev-only **fake-observe seam**
(`app/services/steward/fake.rb`) short-circuits `Steward.read` and answers from
each machine's **`fake-health`** label:

| `fake-health` | Renders as |
|---------------|------------|
| `ok` (default) | reachable, calm, fully hardened |
| `warn`         | reachable, memory/disk under pressure |
| `crit`         | reachable, critically low + hardening drift |
| `offline`      | unreachable |

A **`fake-updates`** label (a count, e.g. `5`) makes the box report that many available
package updates, so an operate machine shows "N pending" and the **Apply Now** act.
Absent → a small default by band (`ok` 0, `warn` 4, `crit` 9). A **`fake-maintenance`**
label (an `HH:MM`, e.g. `02:30`) sets the automatic-maintenance window shown on the page;
absent → `04:00` (a drifted `crit` box reports no window, since unattended-upgrades is off).

The seam is **off unless `STEWARD_FAKE_OBSERVE=1`** *and* the env is dev/test —
it can never act in production. `bin/scenario` sets the flag for you; if you boot
the server by hand, set it yourself:

```bash
STEWARD_FAKE_OBSERVE=1 bin/rails server
```

## Adding a scenario

Drop a `db/seeds/<name>.rb` that `include Scenario` and uses the builders in
`shared.rb` (`reset!`, `machine!(health:)`, `install!(drift:)`, `event!(outcome:)`,
`label!`, `library_app!`). It's picked up automatically by name.

## A note on auditing in the sandbox

An automated axe/pa11y crawl can't hit `localhost:3000` from the dev sandbox
(loopback TCP is blocked except :22, and runner integration sessions 403). Render
via `bin/rails test` there, or run the crawl outside the sandbox.
