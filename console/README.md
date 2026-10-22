# Vilice Console

The human interface to the platform — one Rails app that reaches from a single
box to a fleet. It reaches [Vilice](../vilice/) over scoped SSH, so it runs anywhere:
on the box, your laptop, or a central server.

The spine is **observe vs mutate**: observe reads the record Vilice ships (zero
privilege, changes nothing); mutate issues a named, scoped, recorded command and
writes the act *before* it runs. For the full picture start at
[`blueprint/console/overview.md`](../blueprint/console/overview.md).

## Running it

Prerequisites:

- Ruby 4.0.7 (see `.ruby-version`), Rails 8.1
- [`boxcar-rails`](../../boxcar-rails) as a sibling checkout — it's a path gem
  (`gem "boxcar-rails", path: "../../boxcar-rails"`)

Credentials are your own — the repo ships none
([`secrets-come-from-the-deployment.md`](../decisions/secrets-come-from-the-deployment.md)).
Before you add a real machine, make a local credentials file holding the keys that
encrypt its SSH key (the seeded demo data needs none):

```bash
bin/rails db:encryption:init     # prints three keys
bin/rails credentials:edit       # paste them under active_record_encryption:, save
```

Both files it writes (`config/credentials.yml.enc`, `config/master.key`) are gitignored.
They encrypt the SSH keys of the machines you add, so keep the master key somewhere safe.

```bash
bin/setup           # install gems, prepare the database, seed
bin/rails server    # http://localhost:3000
```

In production the console reads `SECRET_KEY_BASE` and the three
`ACTIVE_RECORD_ENCRYPTION_*` keys from its environment instead.

Sign in with the seeded operator: `operator@console.test` / `password`.

Data is SQLite; jobs, cache, and cable are the Solid trio in the same database for dev.

## Demo scenarios

Load a whole, self-consistent world — healthy, broken, empty, or large — with one
command, for demos, walk-throughs, and accessibility passes:

```bash
bin/scenario --list             # the scenarios
bin/scenario all_broken         # load one
bin/scenario all_clear --serve  # load it, then boot the server with live health
```

Machine health (online/offline, load, memory, disk) is read live from a box, so the
scenarios use a dev-only **fake-observe seam** to render it without one — gated on
`VILICE_FAKE_OBSERVE=1`, which `bin/scenario` sets for you. See
[`db/seeds/README.md`](db/seeds/README.md) for the scenarios and how health is faked.

Plain `bin/rails db:seed` (and `bin/rails db:reset`) load the `empty` default — an
operator and nothing else. Use `SCENARIO=realistic` for the dev-data world.

## Tests

```bash
bin/rails test
```

The SSH transport is faked in tests (`test/test_helpers/fake_vilice.rb`), so they run
offline with no box. Note: in the dev sandbox, loopback TCP is blocked except :22 — use
`bin/rails test` for rendered assertions rather than curling `localhost`.
