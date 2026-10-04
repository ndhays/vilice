# Vilice Console — Open Questions

> Not settled. Vilice Console's side of the platform. As pieces settle, truth migrates
> into `decisions/` (the why) and `blueprint/console/` (the canonical interface,
> data model, and journeys now live there).

**Last touched:** 2026-06-18.

---

## Agents and the console — its own doc

If an agent does the operating, how does a person stay in charge? The lead idea is that
the console's operate becomes a **gate**: an agent with a read-only key proposes, a
person approves or denies the exact command. Where that gate lives, what it must
guarantee, and whether an agent belongs inside the console at all are in
[agents-and-the-console.md](agents-and-the-console.md).

## The console does not build from a clone

Its Gemfile takes Boxcar as a **path gem** (`../../boxcar-rails`), a checkout that sits
beside this repository and is not in it. So `bundle install` fails for anyone but the
maintainer. An outside read of the repo found it first, and it blocks three things at
once:

- **Anyone else running the console.** The docs say it can run locally; it cannot.
- **CI for the console.** The Go binary is checked on every push
  (`.github/workflows/ci.yml`); the Rails half has no check at all.
- **A published image** — the build-context note under "App image registry" below.

The ways out are the usual ones: publish Boxcar and take it from a git source or a gem
server, or vendor it into this repository. Not decided, and the first one waits on
whether Boxcar is ready to be public.

## Host keys — whose memory, and who forgets

The console trusts a box's SSH host key on first connect (`StrictHostKeyChecking=
accept-new`) and remembers it in the `known_hosts` of whatever user it runs as. Three
things follow, none decided:

- **The memory is not the console's.** It lives in a file outside the database, so it is
  not backed up with the machines, and in a container it is gone on every redeploy — at
  which point every box is trusted afresh, silently. That is trust-on-*every*-use.
- **First trust is not an act.** Nothing records that a key was accepted, or which.
- **A rebuilt box needs a shell.** The console names the problem and the command, but
  forgetting the old key means `ssh-keygen -R` on the console's host.

The shape this points at: pin the host key **on the `Machine`**, record accepting it and
record replacing it, and offer *Trust the new key* on Machine Settings as a witnessed act
that shows both fingerprints. Open: whether the first key is accepted on connect or
shown for confirmation alongside the authorize line, which already has the operator on
the box and able to read its fingerprint.

## Vilice Console deploys Vilice Console — the self-update POC

The sharpest proof of the whole model: **Vilice Console updates itself by SSHing into the
Vilice on its own box** — the same scoped, recorded connection it uses for any machine,
just pointed at localhost. No special self-update path, no in-process magic: Vilice Console-
on-the-box is simply one more machine in the fleet, and its own deploy rides the exact
operate-scoped, witnessed channel as everything else. If the platform can replace its own
control plane through its own front door, the front door is real.

Mechanically it's the normal blue/green Quadlet deploy aimed at the local box: pull the
new Vilice Console image, start the inactive color, health-check, flip Caddy, drain the old —
the running Vilice Console hands off to its successor and exits on SIGTERM. The interesting
edges: the connection must outlive the process issuing it (the old color is draining while
the new one takes traffic), and this is exactly the case the OOM-override section guards —
self-deploy is when Vilice Console-on-the-box is most load-sensitive.

Open: does Vilice Console hold a standing scoped connection to its own Vilice, or open one
per deploy like any other machine? Lean toward **no special case** — localhost is just a
`Machine` row with an operate key — which keeps the POC honest. Ties to "Vilice Console runs
anywhere", the OOM per-app override, and the replica/deploy strategy below.

The general form — letting *any* app redeploy itself through a narrow, app-pinned grant —
is the **self-update scope** open question in
[vilice-open-questions.md](vilice-open-questions.md). Vilice Console-deploys-Vilice Console is
just that scope's first customer.

**Two halves, one version.** "Update Vilice Console" is really two moves on different
channels: the **Vilice Console container** is redeployed like any app (the blue/green deploy
above), driven by Vilice Console or by hand —
`ssh _vilice@box deploy console --image …@sha256:…`; the **Vilice binary** is the
privileged floor, replaced only through its own signed channel — **never by Vilice Console**,
which is never root ([create-machine.md](create-machine.md),
[ceiling-is-the-machine](../ceiling-is-the-machine.md)). The platform ships as one
`VERSION`, so a full upgrade is both halves in order — Vilice first, then the Vilice Console
image against it — kept a known-compatible pair by the [versioning](../versioning.md)
contract.

The Vilice half is **settled and out of this doc**: the procedure, and why there is no
`vilice upgrade` command, are canonical in
[blueprint/vilice/provision.md](../../blueprint/vilice/provision.md#upgrading-an-installed-vilice).
What stays open here is only the *Vilice Console* half — the self-update scope above.

**You never need Vilice Console to update Vilice Console.** Vilice is daemonless and lives on
the box, so any operator with a scoped key (or the console) can redeploy or roll back from
the CLI. The in-app self-drive is a convenience on top of that floor, never a dependency —
and the break-glass when the control plane is wedged.

**State has to outlive the container — and the app has to say so.** Vilice Console's data
(the fleet's keys + its own record) must sit on a **persistent volume**, or a redeploy
swaps the code and loses the memory. The Vilice deploy spec already carries `volumes`
([deploy-config-model.md](deploy-config-model.md): a volume is a ref to data that survives
every deploy). **Closed (slice 1):** the `App` now declares volumes — `config.volumes`,
carried into `deploy_envelope`, validated against the box's `Volume=` format, surfaced on the
new/show pages ([data-model.md](../../blueprint/console/data-model.md) `App`). That fork
resolved toward the **general** per-install field, not a Vilice Console-only special case: any
app declares its own volumes. **Still open:** whether Vilice Console's *own* volume then needs
extra protection (named, never pruned on `remove`) on top of the general field — and the
**volume-name uniqueness** guard on a shared box ([journeys.md](../../blueprint/console/journeys.md)).

## Installing Vilice Console in the first place — genesis of the control plane

Self-update assumes Vilice Console is *already* an app the fleet knows. How does it get there
the first time? Two shapes, not yet chosen:

- **Baked into the App Library, protected.** Vilice Console ships as a built-in catalog entry
  that can't be edited or removed and whose core config is fixed (image source, the volume,
  the self-pin) — you install it onto a box like any other app, but you can't misconfigure
  the thing that runs the control plane. Simple, lives entirely Vilice Console-side; the risk is
  a special case in a layer meant to be plain curation ([app-library.md](app-library.md)).
- **Vilice installs Vilice Console itself.** A Vilice-native bootstrap — `vilice` brings up
  its own control plane from the CLI with no Vilice Console in the loop (the chicken-and-egg
  seed). Cleaner for the very first box and for break-glass (stand up the UI from a bare
  prepared box), but it puts knowledge of a specific app into the substrate, which
  ceiling-is-the-machine works hard to keep out.

These pair with the existing genesis decisions: the box self-bootstraps and authorizes
Vilice Console's operate key during provisioning ([create-machine.md](create-machine.md)),
and the per-app **self-update scope** ([vilice-open-questions.md](vilice-open-questions.md))
is the narrowest grant a born-on-the-box Vilice Console could hold to push its own successor.
Decide the volume/identity model (above) first — genesis and self-update share it.

## Where the layering landed

The console's own layering — machine view, placement, tenancy — is settled in
[`console-layers.md`](../console-layers.md), and the reconciliation rule in
[`drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md). What is
still open here is the **build**: the `App.project` inversion (the prerequisite for
either engine), then `vilice-intentions`, then `vilice-projects`. The machine view is
built and is the floor.

## Secret & env UI

How the operator declares an app's environment, and which entries are secret. Direction
chosen: **secret by default** (the fail-safe — forgetting protects rather than leaks),
in one Environment panel with two visibly-distinct modes — masked/guarded secret vs
plain public — labelled by consequence (public is recorded with the deploy; secret is
kept off the record). Maps 1:1 to Vilice's two delivery channels. Full plan:
[vilice-open-questions.md](vilice-open-questions.md). The **App-side declaration** —
each env entry as `{ key, required?, secret?, default }`, driving the app form — is in
[app-library.md](app-library.md); this UI is its deploy-time counterpart.

## OOM priority — don't kill the control plane first

Under memory pressure the kernel's OOM killer should not pick Vilice Console first — losing
the control surface exactly when the box is in trouble is the wrong failure.

*Mechanism settled (Slice B, 2026-06-08):* every Vilice-deployed app already gets
`OOMScoreAdjust=100` on its Quadlet unit, so under pressure the kernel sacrifices an app
before the control plane (Caddy, sshd, the record). See
[quadlet-deploy.md](../quadlet-deploy.md).

**Still open:** that default makes Vilice Console-on-the-box *more* killable, not less. The
fix is a **per-app override** — a `deploy` spec field letting an app declare its own
`OOMScoreAdjust` (a protective negative value for Vilice Console), the later spec field Slice
B deferred. (Per "Vilice Console runs anywhere", this only matters when Vilice Console is actually
on the managed box.)

## The heartbeat — ingestion

**Who records is settled** (`decisions/two-records.md`): Vilice is the sole recorder of
the *box*; Vilice Console never authors the box's record — it **mirrors** it via a cached
scoped-SSH read (no second recorder), and keeps its **own** authoritative record of
control-plane acts. Vilice Console's record is **not** hash-chained (the box chain is the
external anchor). The displayed chain merges the two; authored vs witnessed falls out by
layer. The live observe round trip + per-machine status are built.

**Built (Wave 2.2):** the `vilice record` read verb (entries + chain-verify); Vilice Console
reads it cached and **merges** it with its own record into one chain (`ChainItem`,
authored vs witnessed by actor), with a **chain-integrity** line on the machine page.
Vilice Console's own record gained its first real writer — attributed, append-only label
edits (`decisions/two-records.md`).

**Built (2026-06-17): the live projection.** A status read now reconciles the box into
Vilice Console's stored columns — `Machine#status`/`last_seen_at` and
`Placement#current_image` — in the read path, so the **Now**/Status page exceptions
(unreachable, drift) and the app rollups read something true instead of a column
nothing wrote. `FleetObserveJob` runs the read fleet-wide on a cadence so the page is
fresh without a per-box visit. This is the *current-state* mirror; the *historical* index
(`Snapshot`/box-entry persistence) below is still open. See
[`../observe-reconciliation.md`](../observe-reconciliation.md) and
[`status-signals.md`](status-signals.md) (which also tracks the `failed` signal — blocked
on Vilice reporting per-app container state).

**Still open:**

- **Persistent mirror + Vilice Console's own-record schema** — today the chain renders from
  the live cached read + `Event`; whether `Event` becomes Boxcar `Eventable` (and gains
  the box entries persisted for cross-fleet query) is deferred to the **Boxcar audit**.
- **Dedup** — a Vilice Console-issued box command can appear both as its own `Event` and as
  a box entry under our client name; the merge doesn't reconcile them yet (no overlap in
  practice today).
- **`Snapshot` (history) ingestion cadence** — the *live* projection is reconciled on
  read (built, above); persisting `Snapshot` rows over time for the cross-fleet trend is
  still on-demand vs. background. Sweep **cadence tuning** (large-fleet batching, backoff
  on long-down boxes) is the open edge of `FleetObserveJob` — see
  [`status-signals.md`](status-signals.md).
- Where Vilice Console's observe key lives in a real deployment (not `/tmp`; seeds read
  `/tmp/sy_key` only for local dev).

## App image registry — ghcr to start

Vilice Console (and other apps) build to a container image that Vilice deploys. Start with
**ghcr.io**; roll-your-own registry is the open alternative. **Sub-question (real):** a
deployable image needs Boxcar *in the build context*, but locally Boxcar is a **path
gem** pointing at a sibling checkout — which Docker/Podman builds can't see. Options:
`podman build --build-context boxcar=../../boxcar-rails` (+ COPY in the Dockerfile),
a git source for the image build, or vendoring at build time. Pick one when `make
image` needs to actually ship.

## Secrets & credentials — what belongs in an open repo

Vilice Console is public (AGPL) **and** what the maintainer runs for clients, so this is the
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
- **Master-key custody + rotation**, documented — consistent with Vilice's own key
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

Open shape — migrate is a **composite of existing primitives**, not a new Vilice command:
deploy the same spec on the destination box → health-check → flip the route → remove from
the source (blue/green across *machines* instead of colours). Questions: is it one
witnessed ceremony or a guided two-step (place, then retire)? what carries over — hostname
(must move with it, and is unique-per-machine so the source must release it), volumes
(data does **not** follow; same stateful caveat as replicas — migrate is clean only for
stateless apps or externalized data)? Likely a v-next item; note it so the gap isn't lost.
