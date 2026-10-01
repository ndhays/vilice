# The release command — running migrations without opening a door

> **Proposed 2026-08-19, not built.** A deploy has nowhere to run `db:migrate`, which is
> the gap that stops an ordinary Rails or Django app from working on Vilice at all —
> including the console itself, which we dogfood. This settles the shape so the build is
> reviewable; the parts still genuinely open are marked as such at the end.
>
> Reading order: [`no-key-gets-a-shell.md`](../no-key-gets-a-shell.md) is the rule this
> has to survive, [`app-config-is-the-artifact.md`](../app-config-is-the-artifact.md) is
> the pattern it follows, and [`blueprint/vilice/deploy.md`](../../blueprint/vilice/deploy.md)
> is the sequence it slots into.

---

## The problem

Blue/green means both colors share the app's volumes and talk to the same database. A
schema change has to happen **once**, at a known point, with the new code's migrations —
and today there is no such point. The options people actually reach for are:

- **Migrate in the entrypoint.** Works, and is what everyone does today. But it runs on
  every container start including restarts and both colors, it races when two colors
  overlap at the flip, and a failed migration becomes a crash-loop that the health check
  reports as *unhealthy* rather than *the migration failed*. Illegible in exactly the way
  this project minds.
- **Get a shell and run it.** Refused, permanently, and not up for revisiting.

## What is actually being asked for

Not new power. **A new place to write it down.**

An operate key can already deploy any digest-pinned image, whose entrypoint is arbitrary
code by the same author, running with the same env, the same secrets, the same volumes and
the same network. A release step reaches nothing further. What is new is only the ability
to *choose the command*, and that is a question about where the string comes from.

## The decision: declare it, don't pass it

**`release` is a field on the AppConfig, alongside `port`, `health`, `env` and `volumes`.**
It is part of what the app *is* — curated once in the App Library, carried in the deploy
envelope, persisted in app-state, and covered by the spec digest, so changing the command
changes the spec and that change is recorded.

It is **not** a flag on `vilice deploy`. A per-invocation string would mean the same image
deployed twice could behave differently depending on what somebody typed, which breaks the
one thing the digest pin exists to guarantee.

And it is **not** a general `vilice exec`. That would be a standing capability every
operate key carries forever, untied to any deploy — the thing
[`orchestrators-are-clients.md`](../orchestrators-are-clients.md) means by "a verb Vilice
does not have is a verb the orchestrator cannot perform."

### It is argv, never a shell

```
release: ["bin/rails", "db:migrate"]      not      release: "bin/rails db:migrate"
```

Exec'd directly. No `sh -c`, no metacharacters, no `&&`, no `|`, no `$( )`. This is
[`no-key-gets-a-shell.md`](../no-key-gets-a-shell.md) applied one level down, and it buys
three things at once: the recorded line is unambiguous, injection through a declared value
has nowhere to go, and a multi-step release is forced into **a script inside the image**
(`bin/release`) — where the digest covers what it does.

An allowlist of *known* commands was considered and rejected. `bin/rails` is not a
migration tool, it is an arbitrary code runner; whoever built the image decides what
`db:migrate` executes, and you already trusted them completely when you deployed it. The
allowlist would guard the side door while the front door stood open, break on every
legitimate multi-step release, and put Vilice in the business of knowing about
frameworks — the shape [`provider-boundary.md`](../provider-boundary.md) refused for
clouds and [`backup.md`](../backup.md) refused for databases.

### Where it runs in the sequence

Between the pull and starting the new color:

```
1. resolve + record the spec by digest
2. materialize secrets
3. pull the image
3.5  ← run the release command, from the new image
4. write + start the inactive color's unit
5. health-check it
6. flip Caddy
7. retire the old color
```

After secrets, because it needs database credentials. Before the new color starts, because
that is what makes **a failed release change nothing**: no unit was written, no color was
started, the old one is still serving. The same fail-safe the health gate already provides,
extended one step earlier.

The cost is honest and belongs in the docs: the old code briefly runs against the new
schema, so **migrations must be backward-compatible for one release**. That is the
expand/contract discipline every blue/green system requires (Heroku's release phase is the
same shape), not something this design invents.

### It runs detached, and is not `--rm`

```
podman run -d --name <app>-release-<spec-digest-prefix> …   then poll for exit
```

Three reasons, in order of weight:

- **An interrupted migration is worse than a failed one.** Attached, the run's lifetime is
  tied to the SSH connection, and a dropped connection SIGHUPs it into a half-applied
  schema that neither version of the code expects. This would be **the first step in the
  deploy where interruption is worse than failure** — every other step is safe to
  interrupt, because a half-pull is discarded and a color that never flipped never served.
- **`--rm` deletes the evidence at the moment you need it.** The container is gone before
  its logs can be read, making capture the only copy and a bug in capture a total loss.
- **The name gives idempotence.** Keyed to the spec digest, a retry can tell *already
  running* from *already succeeded* from *failed*, instead of blindly re-running a
  migration that may be half-applied.

Reaped on success, **kept on failure** — the stopped container is evidence, the same shape
as the pending `Event` the console leaves when an act is issued and never settles. A later
successful deploy of the same spec clears its predecessor.

### Everything else follows from "it is part of deploy"

- **One act, not two.** `deployed` settles ok/failed as it always did; the release is a
  sub-step, like the pull and the health check. The blueprint's live-watch note already
  describes the sequence as sub-steps of one act.
- **Scope is `operate`.** No new verb, no new rung.
- **The spec digest covers it**, so changing the release command changes the spec, which is
  recorded and verifiable like every other field.
- **Absent by default.** No declared release, no step, no container. Most apps declare
  nothing.

## The honest limitation

**This relocates the capability; it does not remove it.** An operate-scoped operator can
declare `release: ["curl", "…"]` and it will run, with the app's secrets in its
environment. The defence is not prevention — it is that the declaration is recorded, the
spec digest covers it, and changing it is an act. That is the same defence the whole
system runs on, and this document should not be read as claiming otherwise.

**And `status` does not show it.** `collectApps` is built from `podman ps` — a purely
observed view of what is running, which never reads app-state — so no declared field
appears there, including `Backup`, which has had the same gap since it shipped. A declared
command that runs with the app's secrets and that nothing displays is close to the ambient
authority [`registry-credentials.md`](../registry-credentials.md) refuses on principle.
Closing it means deciding whether `status` merges declared state with observed state,
which is a shape question worth its own change rather than a rider on this one.

Containment is real but partial, and worth stating precisely: the release container is
rootless, so an escape lands as the `_vilice` user and not root; it cannot write a Quadlet
unit, touch Caddy's config, or reach another app's volumes. It **can** do anything the app
itself can do — read the app's data, use the app's secrets, reach the network — because all
three are requirements of the feature.

One implementation rule protects the rest: **Vilice constructs the container's flags; none
are ever passed through.** The moment anything accepts operator flags, `--privileged` walks
straight past the boundary.

## Still open

- **Timeout.** A migration can legitimately take minutes. A constant (say 600s) is the
  boring start; whether it needs to be declarable per app should wait for a real app that
  needs it.
- **`--skip-release`.** There is a genuine emergency case (a wedged migration you must
  deploy past) and an obvious hazard (a safety step with a documented bypass is a safety
  step that gets bypassed). Not decided. Leaning no until someone hits the case.
- **Success output.** Failure output must be captured onto the act. Whether a *successful*
  migration's output is worth keeping is unclear, and keeping it means every deploy carries
  a blob nobody reads.
- **N boxes runs it N times.** An app on three boxes gets three release runs. Rails'
  advisory lock makes that serialize rather than corrupt, which is luck rather than design.
  This is [`install-journeys.md`](install-journeys.md)'s rollout-orchestration gap wearing
  another hat, and the honest v1 answer is to document it and let it become an argument for
  solving that.

## The dependency worth naming before building

A migration has to reach a database. If it is a managed one, or on another box, this design
is complete on its own. **If it is a container on the same box, it is not** — there is no
supported way to run an accessory and connect to it, and
[`provider-boundary.md`](../provider-boundary.md) says so: *app-to-app traffic has no path
at all today.*

So "a Rails app with migrations" works today only against an external database. The on-box
accessory case needs the app-to-app network model first — and that model should be decided
**with** connectivity rather than after it, because the only mechanism available on one box
is the shared host loopback, and enabling `web → postgres` that way enables
`anything → postgres` at the same instant.
