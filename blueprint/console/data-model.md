# Steward Console — Data Model

> The domain in tables. Three decisions are settled inline (tenant boundary, key
> custody, read strategy). **Steward is always the source of truth for observe data** —
> these tables are the control plane's own state plus a re-derivable lens over the record.

**Status:** Built (first cut) + the `Label` table. Last touched 2026-08-03.

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
- `name` (unique), `port`, `health`, `description`, `env` + `secret_files` (jsonb).
  **Image lives on its versions, not here.**
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

### `Install` — a deployed app
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
- `count` (default 1) — **the intention**: how many boxes should serve this. A claim about
  what was asked for, never a reading of what is. Nothing reconciles it
  (→ [drift-is-surfaced-never-closed.md](../../decisions/drift-is-surfaced-never-closed.md)):
  the gap it opens is closed by a named act or it stays open.
  - `Install#serving_count` is the other half — targets the **box** reports running, on a
    machine we can still reach. A target we placed but that isn't up yet does not count,
    and neither does one on an unreachable box.
  - `Install#placement_gap` is `serving − count`, signed: negative is short, positive is
    more than asked for. `in_step?` is the zero case. **Deliberately not folded into
    `install_status`** — an intention is not a state, and the UI keeps them apart.
  - `Install#replicable?` gates `count > 1`, and is **derived, not stored**: an install is
    replicable when it declares no volumes. Replication is stateless-only (a volume is data
    on *that box's* disk, so N replicas are N diverging datasets), and deriving it from the
    spec means the gate can never disagree with the spec the way a flag could. A stateful
    install is refused a count above 1 at validation, not merely discouraged in the form.
- **Validated against the box, since these deploy verbatim** (same as `App`, mirroring
  `steward` `validateState`): `name` is box-safe `[A-Za-z0-9_-]` — it's the box's own
  identifier (`apps/<name>.json`, volumes, unit), prefilled from the app name and not
  dash-cased; `port` 1024–65535 or blank; `health` starts with `/` or blank. Each `volumes`
  entry mirrors the box's `Volume=` line (`steward/internal/pack/app/quadlet.go`): `source:/container-path[:opts]`
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
