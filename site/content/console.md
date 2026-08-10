---
nav: console
title: Steward Console
---
# Steward Console

Steward Console is the human interface. It is a Rails app, and it holds no privilege of its
own: it drives [Steward](/index.html) on each machine over scoped SSH, reads the record, and
operates it. It solves a plain problem — running apps across many machines without giving up
ownership of them, and without a privileged daemon in the middle.

**One console, many boxes.** A fleet is not a mode the console switches into; it is the list
of machines it holds a key for. One box or a hundred is the same code, the same screens, and
one row per machine.

That works because **a box never knows it is in a fleet.** Steward has no cluster membership,
no peer discovery, no awareness that another machine exists. Each one is a sealed door. So
there is nothing to coordinate between them, and nothing for a separate fleet program to do —
the console simply holds N keys and knocks on N doors, one at a time. The cost of that is
honest: a fleet action is N recorded acts, not one atomic act.

## The Machine View

A box's page is shaped by what the box reports. Sections exist because it says what it
was prepared for, not because the console assumed — a balancer shows no Apps section at
all, because that machine has no container runtime and genuinely cannot deploy.

Deploying from here needs **no project and no plan**: paste the app's
[AppConfig](/apps.html#appconfig), and it is sent to the box and discarded. What is
running afterwards is read back from the machine. Nothing about the deploy is stored in
the console, because the box's record already is the record.

Coordinating one app across several machines is a different job, one layer out — that
is where a stated intention, and any drift from it, lives.

## Observe and Mutate

Everything Steward Console does is one of two things, kept apart on purpose.

- **Observe** — read the record Steward ships: status, the activity feed, health over time. It
  holds no privilege, opens no socket, and changes nothing. Most of the app is this.
- **Mutate** — issue a named, scoped command to a box over SSH. Every mutation is written to
  the record *before* it runs. Nothing happens off the books.

## The Nouns

Three things make up the domain.

- **Machine** — a Steward box, reached over scoped SSH. It is dedicated to one project by
  default. Sharing across projects is possible, but only with an explicit sharing model.
- **Install** — a deployed app. It is an [AppConfig](/apps.html#appconfig) placed on one or
  more machines.
- **Project** — a client, and the way to own and group installs. Optional: an install
  belongs to a box, not to a client, so you can place an app without creating one.

## How It Reaches a Box

Steward Console reaches each machine the way the CLI does. It holds a per-machine SSH key,
authorized on the box at a scope — `observe` to read, `operate` to deploy. That is all it
needs, so it runs anywhere: a container on the box, your laptop, or a central server watching a
fleet. Each machine's private key is stored encrypted, so revoking one box never touches
another.

## Install

Steward Console runs like any other app. You deploy it from an [AppConfig](/apps.html#appconfig), the
same as anything else.

1. Authorize Steward Console on the box — [admit a key](/index.html#authentication--scoped-ssh)
   with a named client at `operate` scope.
2. Build its [AppConfig](/apps.html#appconfig) and deploy it. The worked example on that page *is*
   Steward Console's own config.

Steward Console's one secret is `RAILS_MASTER_KEY`. Steward injects it as container env, out of the
record. It unlocks the keys that protect each machine's SSH key at rest, and decrypts the rest
of Steward Console's credentials, which ride inside the image. Then sign in and start operating
machines — others in the fleet, or, slightly meta, the very box it runs on.

## Run From Source

Steward Console lives in the [monorepo](https://github.com/ndhays/steward) under
`console/`:

```bash
cd console
bin/setup           # install gems, prepare the database
```

It encrypts each machine's SSH key at rest, so it needs its own encryption keys. Generate them
once and add them to your credentials. They are *yours*, per checkout, and never committed:

```bash
bin/rails db:encryption:init   # prints the three keys
bin/rails credentials:edit     # paste them under active_record_encryption:
```

Then run the app and its tests:

```bash
bin/rails server
bin/rails test
```

### Boxcar

Steward Console is built on **[Boxcar](https://boxcar.run)** — a Rails pattern language that encodes
the Agora articles as composable concerns: identity, the accountable record, scoped decisions.
It is an ordinary gem dependency, pulled in by `bin/setup`. The two are developed in tandem.
