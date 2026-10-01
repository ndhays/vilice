# Deploy Config Model — the config is the app

> High-level frame, not settled. What a "deployable app" *is*: **one config object that holds
> values and references** (to code, data, secrets), so the deploy spec, the Steward Console DB, and
> the box's stored state all agree on the same object. Refines the mechanism in
> [`decisions/declarative-deploy.md`](../declarative-deploy.md) upward into a model.
>
> **Opened:** 2026-06-09.

---

## The frame: the config is the app

One object, not three peers. **The config *is* the app** — its manifest, its head, its
identity. Everything else it contains is either a **literal value** or a **reference**: a
handle to something kept apart because it's immutable, heavy, or secret.

- **image** → a reference to *code* (immutable → lives content-addressed in a registry)
- **volume** → a reference to *data* (heavy + mutable → lives on disk, backed up by time)
- **secret** → a reference to a *sensitive value* (kept off-record → lives in the secret store)

So the config is just **values + references**, where a reference is a pointer to a thing too
big, too secret, or too locked to inline. That is the whole model — and the simplification
over Kubernetes, which needs ConfigMap / Secret / PVC / Ingress / Deployment as *separate
kinds* only because it schedules across a cluster. One box needs one document.

| Object | Role | Pinned by | Lifecycle |
|--------|------|-----------|-----------|
| **Config** | the app's manifest / identity — *is* the deploy | its own digest | changed deliberately |
| ↳ image *(ref → code)* | what runs | content digest (config pins it exactly) | replaced every deploy |
| ↳ volume *(ref → data)* | what persists | a name/handle (contents live apart) | survives every deploy; backed up by time |
| ↳ secret *(ref → sensitive value)* | sensitive config | a name (value off-record) | rotated independently |

**Two kinds of reference, by what the digest pins.** The config *fully determines the code*
(image by content digest) but only *names* its data and secrets — their contents live and
change on their own. Not a gap: you *want* data to outlive the config and secrets to stay off
the record. The config pins code exactly and grips data/secrets by the handle.

**A running app's identity is name + config, not code.** Because the image is just a field, a
config can swap the whole app — so a deploy isn't "update the code," it's "make this name run
this config." `App` is the *slot*; the config is what fills it; history is the sequence of
configs applied to that slot over time. (This also retires the self-update worry: there's no
structural image-vs-config boundary to defend — authority is simply *which fields of the one
document* a scope may edit.)

A **deploy** stays one sentence: *bind a config (which names its code, data, and secrets) to a
machine at time T, and record it.* Rollback = reapply a prior config. The record commits to the
config by digest — identity is the *digest*; the *date* is the deploy event, not the identity.

## The slot — identity vs. content

A **slot** is the app's *stable identity* — the name that stays put while every version comes
and goes. The config is what's *in* the slot right now (think socket, mount point, a chair with
a job title). A deploy doesn't change the slot; it seats a new config in it. The slot is already
physically present in both layers, just unnamed:

- **On the box:** the filename `/var/lib/steward/apps/<name>.json` is the slot; the contents are
  the current config. One file per slot.
- **In Steward Console:** the `App` row is the slot — it should *point at* a series of configs
  (one marked current), not *be* the config.

What this buys, and why it's the spine of the save/archive + Steward Console work:

- **Data and history hang off the slot, not the config.** The volume belongs to the slot's
  continuity, so it survives every config swap (which is *why* data is a reference, not a value).
  A slot is "a name + a timeline of configs"; rollback = re-seat a prior config in the same slot.
- **Blue/green colors are NOT slots.** `<name>-a`/`-b` are two transient implementations of one
  slot during a cutover — machinery, not identity.
- **Save/archive = the slot's timeline.** Today the box keeps only `prev_image`; the slot view
  says keep each prior *config* so any A→Z rollback is just a re-seat. Natural shape:
  `apps/<name>/current.json` + `apps/<name>/history/<digest>.json`. **Settled:** the AppConfig is
  a first-class, digest-addressed, self-versioned artifact and the slot holds a *timeline* of them
  — see [`app-config-is-the-artifact.md`](../app-config-is-the-artifact.md). (That decision picks
  files-on-the-box for the timeline; folding it into the record stays a possible *addition* for
  forensics, not the primary store.)

("Slot" is a placeholder name — could be the app's *identity*, the *App it fills*, etc.;
let the better word surface as it's built.)

## What's in App Config

What varies between apps / deploys — and where it stands today (`appState` in
`steward/deploy.go`, stored at `/var/lib/steward/apps/<name>.json`):

- **hostnames** — routing. ✅ today
- **env** (non-secret config) — ✅ today, recorded
- **secrets** — names in config; values in the Podman store, off-record. ✅ today
- **volume mounts** — the *declaration*, not the data. ✅ today
- **port** the app listens on — ✅ today (app-owned, really)
- **health** path — ✅ today (app-owned)
- **resource limits** (OOM score, memory) — *not yet a field*; Quadlet has a default, the
  per-app override is the open Slice-B item ([quadlet-deploy.md](../quadlet-deploy.md))
- **replicas / placement** (which machine, how many) — Steward Console's `Placement` carries
  strategy/position; **not in the box spec**. AppConfig is *scale-free by construction*
  (Steward only ever converges one box to one config); scale + exposure live on the App
  — see [`patterns.md`](../../blueprint/console/patterns.md)
- **accessories / linked services** (a Redis or Postgres the app needs alongside it) — **in
  scope** (decided 2026-06-24); the missing axis is being built. A new `accessories` block *inside*
  the AppConfig artifact (so it versions with the config), realized as shared Podman network +
  container-DNS (aardvark-dns) + stable network-aliases, with accessories that outlive app
  redeploys — design in [vilice-open-questions.md](vilice-open-questions.md) "Accessories"
- **pre/post-deploy hooks** — *not built; the genuinely open one (below)*

Note the **image digest itself** sits at the boundary: the config *points at* a code
version, but the code is its own axis. Keep them separate so "update the code" and "change
the config" stay different, separately-witnessed acts.

## Is there an industry standard?

Yes — three layers of prior art, and we already sit on this grain:

- **The principle — Twelve-Factor (factor III, *Config*).** "Config is everything likely to
  vary between deploys," strictly separated from code, supplied by the environment. Its
  litmus test (*could you open-source the repo right now without leaking credentials?*) is
  exactly the open-core / private-edges line. 12-factor is dogmatic about *env vars only* and
  says little about volumes/routing/hooks — so it's the principle, not the schema.
- **The enumerations — K8s / Compose / Kamal.** The concrete lists of "what varies."
  **Kubernetes** decomposes it most fully: *ConfigMap* (config), *Secret* (secrets),
  *PersistentVolumeClaim* (data), *Ingress* (hostnames), *Deployment* (image + probes +
  resources + replicas), lifecycle hooks (`postStart`/`preStop`), *Jobs/initContainers*
  (migrations). `appState` is a flattened single-box version of exactly this. **Compose**
  (`compose.yml`) and **Kamal** (`deploy.yml`) are the single-host cousins; **Kamal also has
  explicit deploy hooks** (`.kamal/hooks/`) — the script question, already in our reference
  frame (Kamal is inspiration-only here).
- **The formal match — Open Application Model (OAM).** OAM splits a *Component* (the
  workload/code) from *Traits* (operational config: routing, scaling) and an *Application
  Configuration* binding them. That component-vs-trait line is the academic version of the
  Image-vs-Config split — formalized, not invented here.

Borrow 12-factor's *separation* + *litmus test*, borrow K8s's *enumeration* of what varies,
and keep our single flat JSON spec (OAM's "application configuration") instead of five object
kinds — one box doesn't need five.

## The upgrade story: pre/post-deploy hooks

Migrations, cache warming, smoke tests: the *upgrade story* — smoothing the boundary with what
came before. The key realization: that story is **A→Z, not Y→Z**. The box might be converging
from *any* prior state (offline for months, skipped versions, a fresh volume), not just the
immediately previous one. **Only the app knows how to get from any A to its Z.**

So the release step must live with the code, written as idempotent, forward-converging
*convergence* (run all that's pending, not "the one step against the assumed predecessor"). The
box only *invokes* it before cutover — it never authors or hosts it:

- **In the image (chosen lean):** the app defines a release/converge command; Steward runs the
  new image once before the flip. The migration is *the app acting as itself, in its own
  container* — a named actor in its own scope. Correct (only the app knows A→Z) *and*
  ceiling-safe (no host shell). 12-factor's "release phase."
- **In the config (rejected):** a declared host hook is arbitrary code on the box — it reopens
  the whole ceiling question (what scope? recorded how?), *and* the box would have to understand
  A→Z, which it can't.

Keep **pre/post-deploy** as the outside name (standard nomenclature); understand it as an
image-owned converge step, not a host script. The config holds at most a flag or command name
("run the release step: `bin/release`"), never the migration's content.

## Where the truth lives

Two copies exist: the box's `/var/lib/steward/apps/<name>.json` and (eventually) Steward Console's
`App` row. Proposed split:

- **Steward Console DB = the source you *edit*** — operator-facing, multi-tenant, where a human
  changes the spec.
- **The box's JSON = the *derivable* copy** — reconstructable from the record + what's
  running; it lets the box stand alone with no off-box brain. A deploy is "render the spec,
  send it, the box persists its own copy."

**Settled (2026-06-24):** authoritative-on-conflict falls out once the config is a digest-addressed
artifact — **Steward Console owns desire (editing mints a new version), the box owns reality (it runs a
digest), and drift is digest ≠ digest.** "Adopt the box's running config" is an explicit witnessed
act, not a silent overwrite. See [`app-config-is-the-artifact.md`](../app-config-is-the-artifact.md).
Still open: the box-side ingestion mechanics for the full config (today's observe read mirrors only
the running *image* digest, not the whole spec) — ties to ingestion
([console-open-questions.md](console-open-questions.md)).

---

Refines: [`declarative-deploy.md`](../declarative-deploy.md) (the Slice-1 mechanism) upward
into a model. Ties to: the OOM per-app override and the secret/env UI (both open).
