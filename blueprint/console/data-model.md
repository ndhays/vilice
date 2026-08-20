# Steward Console — Data Model

> The domain in tables. Three decisions are settled inline (tenant boundary, key
> custody, read strategy). **Steward is always the source of truth for observe data** —
> these tables are the control plane's own state plus a re-derivable lens over the record.

**Status:** Built (first cut) + the `Label` table. Last touched 2026-08-19.

## What's wired

All tables below exist as Rails 8.1 migrations + models, and the three settled
decisions are enforced and tested:

- `Machine.owner` + `Machine.sharing` gate the `ProjectMachine` join (Decision 1);
  a box permits a Project only if it owns it, is shared with everyone, or the
  Project is on its allowlist.
- `encrypts :ssh_private_key` keeps key material ciphertext at rest (Decision 2).
- Observe reads run live over scoped SSH and cache in solid_cache (Decision 3) — see
  `app/services/steward.rb`, split into `Steward::Observe` and `Steward::Mutate`. A read
  also **reconciles the stored projection** (`Machine#status`/`last_seen_at`,
  `InstallTarget#current_image`) so the Status page and the drift rollup read something
  true; `FleetObserveJob` runs the read fleet-wide on a cadence
  (→ [observe-reconciliation.md](../../decisions/observe-reconciliation.md)).
- **`Steward::Observe.logs` is the exception to both halves**, and deliberately.
  `steward logs` is a passthrough to `podman logs` — the container is the source of
  truth and Steward stores nothing — so there is no projection to reconcile. And it is
  **not cached**: a status is a projection you compare over time, a log tail is a stream
  someone asked for *now*, usually while watching a deploy, and answering that with a
  30-second-old tail would be a lie in the shape of a feature. Every tail is therefore
  an SSH round trip, so it is **pulled on request and never rendered by default** — the
  same rule that stops a list querying once per row, applied harder to asking a box.
  The app name is re-checked against `Install::NAME_FORMAT` at the seam before it
  reaches a command line.

Partly wired: **ingestion**. The live projection above is reconciled on every read, but
the *historical* index isn't: nothing yet writes `Snapshot` rows from Steward's
`status.jsonl`, and `Event` is populated only by Steward Console's own mutations
(record-before-run) — not yet mirrored from Steward's audit chain. That history is the
open heartbeat question.

---

## Core domain

### `Project` — an entity / client
- The **tenancy** ring: whose work something is. Optional above everything below it — a
  homelab never creates one ([`../../decisions/console-layers.md`](../../decisions/console-layers.md)).
- `name`, `contact_name`, `contact_email`
- `starred:boolean` (home page "latest")
- has_many `installs` (a lens over placement, not a container — an install may have no
  project); has_many `machines, through: project_machines` (M:N)
- has_many `labels` (polymorphic) — see `Label`

### `Machine` — a Steward box
- `name` (unique) — **mirrors the box, not typed**: seeded from `ssh_host` at Add (we
  can't read the box yet), then renamed to the box's reported hostname on the first
  observe (→ [machine-name-mirrors-the-box.md](../../decisions/machine-name-mirrors-the-box.md))
- `ssh_host`, `ssh_port` (default 22), `ssh_user`
- `steward_version`, `last_seen_at`, `status` (`unknown`/`reachable`/`unreachable` enum)
  — `status` + `last_seen_at` are **reconciled from each observe read**, not the live
  cache: a successful read sets `reachable` + stamps `last_seen_at`, a failed one sets
  `unreachable` (→ [observe-reconciliation.md](../../decisions/observe-reconciliation.md))
- `scope` (`observe` | `operate`) — the scope granted to this machine's key
- `owner_id` — the **owning Project** (nullable; a released/fleet-registered box is
  unowned). Deleting an owner is **blocked** until its boxes are transferred. → decision 1
- `sharing` (`dedicated` | `everyone` | `list`, default **dedicated**) → see decision 1
- `balancer:boolean` (default false) — **the Balancer role**, not a fourth primitive
  ([one-primitive-composed.md](../../decisions/one-primitive-composed.md)). A balancer is
  an ordinary box: same scoped key, same record, same ownership and sharing. What makes it
  one is that installs select it and it is told a routing table. A separate Balancer model
  would duplicate address, key, scope and ownership, then have to be kept in step with the
  Machine it already is. Not exclusive — a balancer may still run apps.
- `Machine#routing_table` is **derived, never stored** (`RoutingTable`): one route per
  install that selects this balancer, whose upstreams are the boxes that install is
  *actually serving from*. A placed-but-not-running or unreachable box is **not** an
  upstream — routing to it would turn a placement gap into a 502, and the gap is meant to
  stay visible. Upstreams address the backend's own edge on port 80, not the app's
  container port (that port is published on the backend's loopback and unreachable from
  the balancer); Caddy forwards the Host header, so the backend matches the same hostname
  and hands off to the app.
- Dropping the role **nullifies** the installs behind it, never destroys them — they
  surface as balanced installs with no balancer, a visible problem rather than a silent
  disappearance.
- `ssh_private_key` — **encrypted** (Active Record Encryption) → see decision 2
- `ssh_public_key` — the authorized half (not secret). Steward Console generates the keypair at
  onboarding (`SshKeypair`); the operator `steward authorize`s this pubkey on the box.
  `Machine#authorize_command` renders that line. See
  `../../decisions/open/create-machine.md`.
- has_many `projects, through: project_machines`; has_many `granted_projects, through:
  machine_grants` (the `list`-mode allowlist); has_many `labels` (polymorphic)

### `MachineGrant` — sharing allowlist join
- `machine_id`, `project_id` (unique together). The projects a `list`-shared box accepts
  besides its owner. Owner-managed; `dependent: :destroy` from Project (its permission
  vanishes; the owner's box is untouched).

### `ProjectMachine` — join
- `project_id`, `machine_id`
- validation: the Machine must **permit** the Project (`Machine#permits?`) — it owns it,
  it's shared with everyone, or the Project is on its allowlist. → decision 1

### `App` — an App Library entry
- `name` (unique), `port`, `health`, `description`, `env` + `secret_files` + `release` +
  `accessories` + `processes` (jsonb). **Image lives on its versions, not here.**
- **`processes`** are the app's other containers — a worker, a clock. Each is
  `{ name, command }` and inherits the app's **image, env, secrets and volumes**; only the
  command differs, stored as argv because the box execs it and never meets a shell. They
  deploy and roll back *with* the app, which is the point: a worker deployed separately
  could land on a different digest, and a worker running yesterday's code against today's
  enqueued jobs is a failure the record cannot describe. Copied onto the Install at create
  like everything else here.
- **One collision check covers all three.** Colours, processes and accessories all mint
  container names from the app's, so `App#container_names_are_distinct` enumerates every
  container the app will ever create and refuses a duplicate — the same set the box
  checks, so a name that would clobber a unit file fails where it is typed.
- **`accessories`** are the containers this app needs on the same box and that nothing
  else may reach — a database, a cache
  ([`accessories-belong-to-one-app.md`](../../decisions/accessories-belong-to-one-app.md)).
  Stored in **the box's own spec shape** (`name`, `image`, `env`, `secrets`, `volumes`),
  so `deploy_envelope` hands them across as a copy rather than a translation and there is
  no second definition to keep in step. Copied onto the Install at create like `release`,
  and for the same reason. Validations mirror `validAccessories` on the box: a
  digest-pinned image, a box-safe name that is not `a`/`b` (the deploy colors) and not the
  app's own, and volumes under the bind root.
- **`release`** is the command the box runs once from the new image before the new
  container starts — migrations are the case it exists for
  ([`blueprint/steward/deploy.md`](../steward/deploy.md), *The Release Step*). Stored as
  **argv**, because argv is what the box execs: it never sees a shell, so the form takes
  one line and splits it, and a multi-step release belongs in a script inside the image
  where the digest covers what it does. It sits on the App because it is a property of
  the image the way `port` and `health` are — and an **Install copies it at create**, so
  editing the library later never silently changes what an already-placed app runs on its
  next deploy. That is the same rule the image itself follows: copied from the Version,
  never followed.
- **Declared inputs — names only, no values** (values are supplied at install). `env` is a
  list of `{ key, secret }`: a `secret` entry is an env var delivered **off-record** (the
  box mirrors this — env vs `Secret=type=env`), so "secrets are env vars" with one flag.
  `secret_files` is a list of `{ name, path }` — values mounted as files off-record (a
  config, an htpasswd). Names follow the box's env rule (`[A-Za-z_][A-Za-z0-9_]*`); a name
  can't be both an env var and a file. Edited on the App page; carried in the manifest.
- **Validations mirror the box** (`steward` `validateState`/`validClient`), so a bad
  value fails in Steward Console — before the act — not cryptically at deploy: `name` is
  box-safe `[A-Za-z0-9_-]` (it seeds the install name, which becomes `apps/<name>.json`
  + volumes + unit on the box; **not** dash-cased for you); `port` is 1024–65535 or blank
  (unprivileged containers can't bind below 1024); `health` starts with `/` or is blank.
  Blank port/health mean "no app default" — the box falls back (8080, `/`).
- The **catalog/bookmarking** layer (`decisions/open/app-library.md`) — a curated, reusable
  app definition the admin saves. The top of the three-tier model: **`App` → `Install`
  (a deployment into a Project) → `InstallTarget` (per machine)** — and itself the head of
  its release history (**`App` → `Version`**). Curating it is a recorded own-record act.
  `has_many :labels` (polymorphic, generic metadata). Not a security boundary — the
  un-bypassable image allowlist is a separate Steward-side concern.
- **Portable as a manifest** (`Library`, `apps#export`/`import`). The whole library
  exports to a YAML manifest (apps + versions, **labels omitted** — they're local
  organization, not the app's official definition) and imports back **additively**,
  from an uploaded file **or a URL** (`Library.fetch` — the marketplace path): apps
  upsert by name, versions by tag, nothing is deleted. Two libraries can be imported
  and coexist. Pruning is the deliberate counterweight — `apps#remove_selected`
  bulk-deletes, recorded as one act. The DB stays the store; the manifest is the
  interchange shape (the form a marketplace would publish).

### `Version` — a release of an App
- `app_id`, `tag` (unique per app, e.g. `v1.2.0`), `image` (digest-pinned), `latest:boolean`.
- The library curates which releases exist; **exactly one per app is `latest`** (DB-enforced
  by a partial unique index; `App#set_latest!`). Install picks a version (default latest).
- **Both halves are the release**: the tag is the name a person reads, the digest is what
  is actually pulled. `Version` refuses an unpinned image because the box does, so it
  fails where you type it rather than at the far end.
- **Look up digest** (`Registry.pin`, `POST /apps/:id/versions/resolve`) asks the registry
  what a tag points at and *fills the field in* — a second submit on the same form, so it
  works with no JS. It saves nothing. **Resolution is a read; pinning is a decision**
  ([`a-tag-is-not-a-release.md`](../../decisions/a-tag-is-not-a-release.md)): nothing
  re-resolves afterwards, because a release that quietly followed a moving tag would make
  *what was running* unanswerable. What is stored is the **full** name
  (`docker.io/library/redis@sha256:…`), never the short one typed, because a short name
  implies a registry instead of naming it.
- **Public registries only, deliberately.** A private one needs a credential, and that
  credential lives on the box
  ([`registry-credentials.md`](../../decisions/registry-credentials.md)) precisely so the
  console never holds pull access to your images. A registry that asks for authentication
  gets a sentence pointing at `steward registry-login` and an invitation to paste the
  digest — not a field to put a password in.

### `Install` — a deployed app
- `secret_values` — **encrypted at rest** (Active Record Encryption, the same protection
  `Machine#ssh_private_key` gets) and **resent on every deploy**, so a deploy is
  self-contained: no set-once ordering and no dangling secret waiting for an app
  ([`declarative-deploy.md`](../../decisions/declarative-deploy.md)). Per *Install*, not
  per App — staging and production are two placements of one app and do not share a
  database password. The App declares the names; the Install holds what they are worth.
  - They ride the envelope on **stdin**, never argv, so they are never recorded: the
    chain commits to the spec digest, which covers secret *names* and never values.
  - **Never rendered back.** A value goes in and only ever comes out on its way to a box;
    the form says whether one is held and typing replaces it. A blank field therefore
    means *leave it alone*, never *clear it* — a password input renders empty by design,
    so treating blank as a deletion would wipe every secret not retyped.
  - `Install#declared_secret_names` reads the shape off the App **and its accessories** —
    a database password is the install's to supply even though the database reads it —
    and `missing_secrets` is what the console checks before the ceremony. That check is a
    **refusal, not a warning**, and the difference from the authorize gap is the point:
    reachability is a reading that can be stale, whereas we either hold a value or we do
    not. Refused before the `Event` is written, because nothing was attempted.
  - Only names the current spec declares are sent. A value left over from a name the
    library has since dropped is not something to hand a box.
- `project_id` — **nullable.** An install is a *placement*: this app, on these boxes. A
  Project says whose work it is, which is a separate and outer question
  ([`../../decisions/console-layers.md`](../../decisions/console-layers.md)), so an
  install can have none — you are never made to invent a client to place an app. Where
  there is one it comes from the URL (`installs/new?project_id=`) and narrows the machine
  list to that project's boxes; it is never a form field. The App Library is a directory;
  it has no install action.
- **No uniqueness on `name`.** The name has to be free *on the box* — that is the
  namespace it lands in — and `InstallTarget` already enforces exactly that, independent
  of any project. A per-project scope would both miss the collision that matters (two
  projects on one shared box) and require a project to exist.
- `app_id` (nullable) — the App Library entry it was **installed from**; nil = a custom
  image. Removing the `App` nullifies this (the install keeps running).
- `version_id` (nullable) — the `Version` deployed; nil for custom images. `image` is
  copied from it at install time.
- `name`, `image` (digest-pinned), `hostname`, `port`, `health`, `config` (jsonb) — `config`
  holds the non-scalar spec: `env` and `volumes` (`Install#volumes`), the declarations that
  version with the app, not the data.
- `exposure` (`edge` | `balanced`, default **edge**) — how the app is reached, and the
  reason a count above 1 can or can't mean anything. *On the edge*, DNS points at the box
  and the box terminates its own TLS: one box, one IP, so `count` is pinned to 1 (scaling
  here would need round-robin DNS, rejected). *Behind a balancer*, the box is a backend and
  DNS points at the balancer, so more boxes are just more upstreams. **The console does not
  manage a balancer yet** — marking an install balanced states the topology and unlocks the
  count; pointing something at those boxes is the operator's, and a managed Balancer is
  still pending.
- `balancer_id` (nullable) — which box fronts this install. Only valid when balanced, and
  only pointing at a box that has taken the role; both refused rather than ignored, since
  an install pointing at a box that fronts nothing would look routed and not be. Optional
  even when balanced: an operator running their own edge just wants the count unlocked.
- `count` (default 1) — **the intention**: how many boxes should serve this. A claim about
  what was asked for, never a reading of what is. Nothing reconciles it
  (→ [drift-is-surfaced-never-closed.md](../../decisions/drift-is-surfaced-never-closed.md)):
  the gap it opens is closed by a named act or it stays open.
  - `Install#serving_count` is the other half — targets the **box** reports running, on a
    machine we can still reach. A target we placed but that isn't up yet does not count,
    and neither does one on an unreachable box.
  - `Install#placement_gap` is `serving − count`, signed: negative is short, positive is
    more than asked for. `in_step?` is the zero case, `short?` the negative one.
    **Deliberately not folded into `Install#state`** — an intention is not a state, and
    the UI keeps them apart.
  - **Whether the gap can be closed right now is a second question**, and it is the one
    with a fix attached: *asked for 3 · serving 2* says there is a gap, not whether that
    is a click or an errand. `Install#candidate_machines` is where it could still go —
    operate-scoped, in the project when there is one, not already carrying it — and it is
    **the single definition**, read by the picker, by the page that offers the act, and by
    Status. Three copies of that rule would drift, the way `added` and `placed` did.
  - `Install#ready_machines` narrows candidates to boxes we have **heard from**
    (`Machine#reached?`). Placing works on any candidate — it reaches nothing, the target
    sits `pending` — but the deploy that follows cannot connect to a box that never
    authorized us. So *ready* means ready to **finish**, not merely ready to record, and
    `ready_to_place?` is `short? && ready_machines.any?`.
  - Readiness is a **reading, not a claim**: it is as fresh as the last observe and nothing
    here probes a box. It is surfaced beside the gap and never inside the status glyph.
  - `candidate_machines` takes an optional preloaded **pool** so a list can answer for many
    installs without a query each. Two preloads are required for that to hold — the pool's
    `project_machines` and each install's `install_targets` — and it is pinned in
    `install_test.rb`, because half of it fails silently.
  - **Two gates on `count`, both validations rather than form hints.** `exposure` must be
    `balanced`, *and* the install must be replicable. Either one alone pins it to 1, and
    the stateful gate wins even behind a balancer — a balancer in front of N diverging
    datasets is still N diverging datasets.
  - `Install#replicable?` gates `count > 1`, and is **derived, not stored**: an install is
    replicable when it declares no volumes **and brings no accessory that keeps data**.
    The second is the same fact as the first — an accessory's volume is data on that
    box's disk — so it folds in rather than sitting beside it. Replication is stateless-only (a volume is data
    on *that box's* disk, so N replicas are N diverging datasets), and deriving it from the
    spec means the gate can never disagree with the spec the way a flag could. A stateful
    install is refused a count above 1 at validation, not merely discouraged in the form.
- **Validated against the box, since these deploy verbatim** (same as `App`, mirroring
  `steward` `validateState`): `name` is box-safe `[A-Za-z0-9_-]` — it's the box's own
  identifier (`apps/<name>.json`, volumes, unit), prefilled from the app name and not
  dash-cased; `port` 1024–65535 or blank; `health` starts with `/` or blank. Each `volumes`
  entry mirrors the box's `Volume=` line (`steward/internal/app/quadlet.go`): `source:/container-path[:opts]`
  where `source` is a named volume or host path and the mount path is absolute — a malformed
  mount fails here, before the act.
- has_many `install_targets`
- **The Install *is* the deploy spec.** `Install#deploy_envelope(image:)` builds the
  JSON envelope Steward's `deploy` reads on stdin (`{app:{image,hostnames,port,health,
  env,volumes}}`) — secret *values* never live here (#14's off-record channel). A deploy through
  the mutate ceremony just pins a new `image` digest (compose step).

### `InstallTarget` — Install × Machine
- `install_id`, `machine_id`
- `strategy` (single | replica…), `position`, `desired_image`, `current_image`, `status`
- the old Dispatcher install decision points (one machine vs. replica set) live here.
- **Isolation guard** — validates the install's `name` and `hostname` are unique **per
  machine** (a non-retired target on the same box may not share either). Apps share a
  box's namespace (`apps/<name>.json`, one Caddy, named volumes), so this stops one
  Project clobbering another's app or hijacking its route on a shared box — the
  control-plane guardrail above the box's own boundary. See the isolation rule in
  [`journeys.md`](journeys.md).
- A successful deploy pins `desired_image` (what we asked Steward to run); `current_image`
  is reconciled from what the box reports (observe), not written by the deploy — so
  `in_sync?` is honest drift, not an assumption.
- **The intention is editable; the spec is not, here.** `installs#edit`/`update` reach
  `count` and `exposure` and nothing else, recorded as a `restated intention` act with
  human attribution and no outcome to settle. Restating is not a deploy and not a removal:
  asking for more opens a gap, asking for fewer closes one **without touching a box** —
  targets keep running, and taking an app off a box stays the witnessed `remove` verb. A
  cascade of destructive calls whose only trace is a changed number is exactly what
  [drift-is-surfaced-never-closed.md](../../decisions/drift-is-surfaced-never-closed.md)'s
  first corollary refuses.
- **Creating a target is the act that closes a placement gap** (`InstallTargetsController`,
  `POST /installs/:id/targets`): a person picks a box, the placement is recorded, and the
  deploy follows through the ordinary witnessed ceremony. Placing alone does **not** close
  the gap — the target starts `pending`, and the gap narrows only when the box reports it
  serving. There is no scale-*down* action here on purpose: taking an app off a box is the
  existing `remove` verb, already witnessed.

### `Label` — universal key/value metadata
- polymorphic `labelable` (`Project` or `Machine`), `key` (required), `value` (optional)
- Hetzner semantics: a bare key (`shared`) is valid, as is `env=prod`; a key is
  unique per record (key→value, not key→many). Format-checked, normalized.
- Operator-assigned **metadata you group and search by** — distinct from the
  status/scope badges, which are the system's own truth. `Project`/`Machine`
  `has_many :labels, as: :labelable`. Renders as a segmented two-tone tag.
- Indexed on `[key, value]` for fleet-wide label search (see
  `../../decisions/open/list-search.md`).

### `Setting` — fleet-wide policy (singleton)
- One row, `Setting.current`. `installs_library_only` (default on) gates the install
  flow: installs come from the App Library unless the operator turns it off (then a
  custom image is allowed). A **guardrail, not security** — see
  `../../decisions/open/app-library.md`.

## Observe side — a lens, not the source of truth

### `Snapshot` — status over time
- `machine_id`, `captured_at`, `reachable`, `metrics` (load/mem/disk), `raw` (jsonb)
- ingested from Steward's `status.jsonl` / live reads. **Re-derivable.**

## The record — Steward Console's own, plus a Steward mirror

### `Event`
- `machine_id` / `install_id` / `project_id`, `at`, `actor`, `action`, `summary`, `raw`
- **Outcome lifecycle** — `outcome` (nil → `pending` → `ok`/`failed`), `finished_at`,
  `detail`. A witnessed act is recorded `pending` *before* it runs (record-before-act),
  then **settled once** on the same row when it returns. Instantaneous acts (a label
  edit, a star) carry `outcome = nil` and never settle. The append-only guard freezes
  the facts but permits this single pending→settled transition — see
  [`../../decisions/record-outcome-on-the-entry.md`](../../decisions/record-outcome-on-the-entry.md).
- **Two roles, kept distinct** (see [`../../decisions/two-records.md`](../../decisions/two-records.md)):
  - *Steward Console's own acts* — control-plane mutations with no box (created / linked /
    labelled), **human attribution**, fleet-level groupings, the intent + outcome of
    issued commands (incl. **refused/failed**, which never reach a box), access events.
    **Authoritative; not re-derivable.**
  - *A mirror of Steward's record* — box acts pulled over scoped SSH for unified
    display/search (the "fancy Sentry"). **Re-derivable cache.**
- The displayed timeline (the "chain") merges the two; **authored** (Steward Console ran it,
  human behind it) vs **witnessed** (it appeared in the box record from elsewhere) falls
  out by layer.
- **Not hash-chained.** Steward's on-box chain is the external anchor — anything
  box-touching is cross-checkable against it; a same-DB self-anchored chain would be
  theater. See the decision.

## Auth
- `User`, `Session` — operators who log into Steward Console (Boxcar / Rails 8 auth).
  Steward Console's own **web** auth; distinct from the scoped-SSH keys it holds per Machine.

---

## Decisions (settled this round)

### 1. Tenant boundary — an owned box, shared only on purpose
A box has an **owner** (the client whose hardware it is) and an explicit **sharing**
mode — `dedicated` (owner only, the default), `everyone` (open multi-tenant), or `list`
(owner + an allowlist of `MachineGrant` projects). The `ProjectMachine` join refuses a
Project the box doesn't permit (`Machine#permits?`), so one client's box can't be picked
up by another's project. A box is never wide-open by accident, and an owner can transfer
or release ownership (an unowned box is inert, surfaced on the fleet page). The full why
+ roads not taken (no Owner/Account layer; block-not-nullify on owner delete) is in
`../../decisions/machine-ownership.md`.

### 2. Key custody — Active Record Encryption, per machine
Each Machine holds the SSH **private** key whose public half is `steward authorize`d on
the box, stored with Rails **Active Record Encryption** (`encrypts :ssh_private_key`).
Per-machine keypairs, so revoking one box never touches another. This is the
best-practice default; **no external secret manager** (Bitwarden CLI, etc.) — that would
solve a problem we don't have yet.

### 3. Reads — live from Steward, cached in `solid_cache`
Steward's on-box append-only record is the **source of truth for box data** (status,
the audit chain); Steward Console never authors it. (Off-host shipping, to make the record
survive the box, is still open — see Steward's open questions.) Steward Console reads on
demand over scoped SSH and **caches in `solid_cache`** (DB-backed, shared across
requests, TTL'd) — *not* browser memory, *not* tmp files. `Snapshot` and the **mirror**
half of `Event` are this re-derivable cache; a miss just re-reads Steward.

This is **not** the whole story: Steward Console also keeps its **own** authoritative record
of control-plane acts that no box can see (Article II at its layer). See
[`../../decisions/two-records.md`](../../decisions/two-records.md) — the two-record model,
and why Steward Console's record is **not** hash-chained.
