# Steward Console — Open Questions

> Not settled. Steward Console's side of the platform. As pieces settle, truth migrates
> into `decisions/` (the why) and `blueprint/console/` (the canonical interface,
> data model, and journeys now live there).

**Last touched:** 2026-06-18.

---

## Steward Console deploys Steward Console — the self-update POC

The sharpest proof of the whole model: **Steward Console updates itself by SSHing into the
Steward on its own box** — the same scoped, recorded connection it uses for any machine,
just pointed at localhost. No special self-update path, no in-process magic: Steward Console-
on-the-box is simply one more machine in the fleet, and its own deploy rides the exact
operate-scoped, witnessed channel as everything else. If the platform can replace its own
control plane through its own front door, the front door is real.

Mechanically it's the normal blue/green Quadlet deploy aimed at the local box: pull the
new Steward Console image, start the inactive color, health-check, flip Caddy, drain the old —
the running Steward Console hands off to its successor and exits on SIGTERM. The interesting
edges: the connection must outlive the process issuing it (the old color is draining while
the new one takes traffic), and this is exactly the case the OOM-override section guards —
self-deploy is when Steward Console-on-the-box is most load-sensitive.

Open: does Steward Console hold a standing scoped connection to its own Steward, or open one
per deploy like any other machine? Lean toward **no special case** — localhost is just a
`Machine` row with an operate key — which keeps the POC honest. Ties to "Steward Console runs
anywhere", the OOM per-app override, and the replica/deploy strategy below.

The general form — letting *any* app redeploy itself through a narrow, app-pinned grant —
is the **self-update scope** open question in
[steward-open-questions.md](steward-open-questions.md). Steward Console-deploys-Steward Console is
just that scope's first customer.

**Two halves, one version.** "Update Steward Console" is really two moves on different
channels: the **Steward Console container** is redeployed like any app (the blue/green deploy
above), driven by Steward Console or by hand —
`ssh steward@box deploy console --image …@sha256:…`; the **Steward binary** is the
privileged floor, replaced only through its own signed channel — **never by Steward Console**,
which is never root ([create-machine.md](create-machine.md),
[ceiling-is-the-machine](../ceiling-is-the-machine.md)). The platform ships as one
`VERSION`, so a full upgrade is both halves in order — Steward first, then the Steward Console
image against it — kept a known-compatible pair by the [versioning](../versioning.md)
contract.

The Steward half is **settled and out of this doc**: the procedure, and why there is no
`steward upgrade` command, are canonical in
[blueprint/steward/provision.md](../../blueprint/steward/provision.md#upgrading-an-installed-steward).
What stays open here is only the *Steward Console* half — the self-update scope above.

**You never need Steward Console to update Steward Console.** Steward is daemonless and lives on
the box, so any operator with a scoped key (or the console) can redeploy or roll back from
the CLI. The in-app self-drive is a convenience on top of that floor, never a dependency —
and the break-glass when the control plane is wedged.

**State has to outlive the container — and the app has to say so.** Steward Console's data
(the fleet's keys + its own record) must sit on a **persistent volume**, or a redeploy
swaps the code and loses the memory. The Steward deploy spec already carries `volumes`
([deploy-config-model.md](deploy-config-model.md): a volume is a ref to data that survives
every deploy). **Closed (slice 1):** the `App` now declares volumes — `config.volumes`,
carried into `deploy_envelope`, validated against the box's `Volume=` format, surfaced on the
new/show pages ([data-model.md](../../blueprint/console/data-model.md) `App`). That fork
resolved toward the **general** per-install field, not a Steward Console-only special case: any
app declares its own volumes. **Still open:** whether Steward Console's *own* volume then needs
extra protection (named, never pruned on `remove`) on top of the general field — and the
**volume-name uniqueness** guard on a shared box ([journeys.md](../../blueprint/console/journeys.md)).

## Installing Steward Console in the first place — genesis of the control plane

Self-update assumes Steward Console is *already* an app the fleet knows. How does it get there
the first time? Two shapes, not yet chosen:

- **Baked into the App Library, protected.** Steward Console ships as a built-in catalog entry
  that can't be edited or removed and whose core config is fixed (image source, the volume,
  the self-pin) — you install it onto a box like any other app, but you can't misconfigure
  the thing that runs the control plane. Simple, lives entirely Steward Console-side; the risk is
  a special case in a layer meant to be plain curation ([app-library.md](app-library.md)).
- **Steward apps Steward Console itself.** A Steward-native bootstrap — `steward` brings up
  its own control plane from the CLI with no Steward Console in the loop (the chicken-and-egg
  seed). Cleaner for the very first box and for break-glass (stand up the UI from a bare
  prepared box), but it puts knowledge of a specific app into the substrate, which
  ceiling-is-the-machine works hard to keep out.

These pair with the existing genesis decisions: the box self-bootstraps and authorizes
Steward Console's operate key during provisioning ([create-machine.md](create-machine.md)),
and the per-app **self-update scope** ([steward-open-questions.md](steward-open-questions.md))
is the narrowest grant a born-on-the-box Steward Console could hold to push its own successor.
Decide the volume/identity model (above) first — genesis and self-update share it.

## Where the layering landed

The console's own layering — machine view, placement, tenancy — is settled in
[`console-layers.md`](../console-layers.md), and the reconciliation rule in
[`drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md). What is
still open here is the **build**: the `App.project` inversion (the prerequisite for
either engine), then `steward-intentions`, then `steward-projects`. The machine view is
built and is the floor.

## Secret & env UI

How the operator declares an app's environment, and which entries are secret. Direction
chosen: **secret by default** (the fail-safe — forgetting protects rather than leaks),
in one Environment panel with two visibly-distinct modes — masked/guarded secret vs
plain public — labelled by consequence (public is recorded with the deploy; secret is
kept off the record). Maps 1:1 to Steward's two delivery channels. Full plan:
[steward-open-questions.md](steward-open-questions.md). The **App-side declaration** —
each env entry as `{ key, required?, secret?, default }`, driving the app form — is in
[app-library.md](app-library.md); this UI is its deploy-time counterpart.

## OOM priority — don't kill the control plane first

Under memory pressure the kernel's OOM killer should not pick Steward Console first — losing
the control surface exactly when the box is in trouble is the wrong failure.

*Mechanism settled (Slice B, 2026-06-08):* every Steward-deployed app already gets
`OOMScoreAdjust=100` on its Quadlet unit, so under pressure the kernel sacrifices an app
before the control plane (Caddy, sshd, the record). See
[quadlet-deploy.md](../quadlet-deploy.md).

**Still open:** that default makes Steward Console-on-the-box *more* killable, not less. The
fix is a **per-app override** — a `deploy` spec field letting an app declare its own
`OOMScoreAdjust` (a protective negative value for Steward Console), the later spec field Slice
B deferred. (Per "Steward Console runs anywhere", this only matters when Steward Console is actually
on the managed box.)

## The heartbeat — ingestion

**Who records is settled** (`decisions/two-records.md`): Steward is the sole recorder of
the *box*; Steward Console never authors the box's record — it **mirrors** it via a cached
scoped-SSH read (no second recorder), and keeps its **own** authoritative record of
control-plane acts. Steward Console's record is **not** hash-chained (the box chain is the
external anchor). The displayed chain merges the two; authored vs witnessed falls out by
layer. The live observe round trip + per-machine status are built.

**Built (Wave 2.2):** the `steward record` read verb (entries + chain-verify); Steward Console
reads it cached and **merges** it with its own record into one chain (`ChainItem`,
authored vs witnessed by actor), with a **chain-integrity** line on the machine page.
Steward Console's own record gained its first real writer — attributed, append-only label
edits (`decisions/two-records.md`).

**Built (2026-06-17): the live projection.** A status read now reconciles the box into
Steward Console's stored columns — `Machine#status`/`last_seen_at` and
`Placement#current_image` — in the read path, so the **Now**/Status page exceptions
(unreachable, drift) and the app rollups read something true instead of a column
nothing wrote. `FleetObserveJob` runs the read fleet-wide on a cadence so the page is
fresh without a per-box visit. This is the *current-state* mirror; the *historical* index
(`Snapshot`/box-entry persistence) below is still open. See
[`../observe-reconciliation.md`](../observe-reconciliation.md) and
[`status-signals.md`](status-signals.md) (which also tracks the `failed` signal — blocked
on Steward reporting per-app container state).

**Still open:**

- **Persistent mirror + Steward Console's own-record schema** — today the chain renders from
  the live cached read + `Event`; whether `Event` becomes Boxcar `Eventable` (and gains
  the box entries persisted for cross-fleet query) is deferred to the **Boxcar audit**.
- **Dedup** — a Steward Console-issued box command can appear both as its own `Event` and as
  a box entry under our client name; the merge doesn't reconcile them yet (no overlap in
  practice today).
- **`Snapshot` (history) ingestion cadence** — the *live* projection is reconciled on
  read (built, above); persisting `Snapshot` rows over time for the cross-fleet trend is
  still on-demand vs. background. Sweep **cadence tuning** (large-fleet batching, backoff
  on long-down boxes) is the open edge of `FleetObserveJob` — see
  [`status-signals.md`](status-signals.md).
- Where Steward Console's observe key lives in a real deployment (not `/tmp`; seeds read
  `/tmp/sy_key` only for local dev).

## App image registry — ghcr to start

Steward Console (and other apps) build to a container image that Steward deploys. Start with
**ghcr.io**; roll-your-own registry is the open alternative. **Sub-question (real):** a
deployable image needs Boxcar *in the build context*, but locally Boxcar is a **path
gem** pointing at a sibling checkout — which Docker/Podman builds can't see. Options:
`podman build --build-context boxcar=../../boxcar-rails` (+ COPY in the Dockerfile),
a git source for the image build, or vendoring at build time. Pick one when `make
image` needs to actually ship.

## Secrets & credentials — what belongs in an open repo

Steward Console is public (AGPL) **and** what the maintainer runs for clients, so this is the
open-core / private-edges line (`decisions/licensing.md`) made concrete. Right now
`config/credentials.yml.enc` is committed; it's encrypted and `master.key` is gitignored,
which is standard Rails and safe *as long as the master key stays secret*. The wrinkle:
that file holds the **Active Record Encryption keys**, and those protect
`Machine#ssh_private_key` — real, operate-scoped SSH keys to client boxes. The highest-
value secret in the system shouldn't ride in core just because it's encrypted.

Decide the proper steps (alongside the website/docs pass — this is part of "open and
proprietary, not a contradiction"):

- **Keys out of core.** Per-deployment secrets are a private edge: core should ship
  placeholder/structure only. Candidates — supply AR encryption keys (and other prod
  secrets) via **ENV** / a secret store in production (out of git entirely), or use a
  per-env `config/credentials/production.yml.enc` whose key lives only on the deploy
  host and is never pushed.
- **Master-key custody + rotation**, documented — consistent with Steward's own key
  custody (release key already offline at `~/.keys`).
- **The keys in 586067f are dev-only** — rotate before any real client data, since
  they're now in git history.
- **`SECRET_KEY_BASE` rotation, documented** *(suggested 2026-06-18, not settled)* —
  rotating it invalidates every active session (the Rails-specific dance), distinct from
  the master-key/AR-key rotation above. Worth a short documented procedure (and a note on
  whether it's ENV-supplied in production like the AR keys) so a rotation isn't an
  unplanned logout-everyone event. Suggested topic, not yet a plan.

## Replica / deploy strategy — the build

The model is settled and the reasoning has moved up:
[`one-primitive-composed.md`](../one-primitive-composed.md) (including the rejected
shortcuts — DNS round-robin, in-box replicas — and the floating-IP note for balancer HA),
canonical in [`patterns.md`](../../blueprint/console/patterns.md). There is no Fleet
object: a fleet is an App with count > 1 behind a balancer.

What is left is build, not model:

- the balancer's **reconciled Caddy** config and reload loop;
- **rollout orchestration** — deploy-to-N with a policy (all-at-once / rolling / canary),
  a composite of the existing ceremony, no new primitive;
- **provisioning the backends**, and the **private-backend jump** (`via` / ProxyJump);
- **balancer HA** (two boxes + floating IP).

Single-machine deploy and rollback are built. The app flow's placement step ships an
**interim Single/Fleet stub** and reworks to **Box × Exposure × scale** once the balancer
lands.


## Migrate an app to another machine — a missing verb

Today an `Placement` is created on one machine and only ever `deploy`/`rollback`/
`remove`d *there*; there's no "**move this app to that box**." The "deploy game" pressure
test surfaced it — dragging a train between yards is an obvious motion, and the model
can't express it. It's distinct from replicas (above): one placement *relocates*, it
doesn't fan out.

Open shape — migrate is a **composite of existing primitives**, not a new Steward command:
deploy the same spec on the destination box → health-check → flip the route → remove from
the source (blue/green across *machines* instead of colours). Questions: is it one
witnessed ceremony or a guided two-step (place, then retire)? what carries over — hostname
(must move with it, and is unique-per-machine so the source must release it), volumes
(data does **not** follow; same stateful caveat as replicas — migrate is clean only for
stateless apps or externalized data)? Likely a v-next item; note it so the gap isn't lost.
