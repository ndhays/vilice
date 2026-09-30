# Steward — Open Questions

> Not settled. The `blueprint/steward/` specs stay silent on these until they are
> decided. When one settles, move the answer into the relevant spec and record the
> reasoning in `decisions/`.

**Last touched:** 2026-09-19.

---

## Off-host shipping — streaming + queryable read-replica

**Snapshot-grade is built:** `backup --machine` ships the record dir off-box (see
[`decisions/backup.md`](../backup.md)). What's still open is the stronger property:

- **Streaming (zero-loss-window).** The record is **append-only**, so this is "ship new
  bytes as they land," not Litestream (whose value is mutable-DB replication). The earlier
  "SQLite + Litestream for the record" sketch is **reconsidered** — keep the record JSONL
  (immutable via `chattr +a`, zero-dep) and stream the log itself.
- **Off-box queryable read-replica.** Project the shipped append-only log into SQLite
  **off-box**, so Steward Console's read side gets rich SQL without SSH round-trips (the CQRS
  "consume the shipped dump" model). The box stays simple; SQLite never lands on it.

## DNS-01 challenge + Agora-aligned edge/DNS providers

**Implement DNS-01 at some point** — the bulletproof path to HTTPS behind a TLS-terminating
CDN (and the only way to get *wildcard* certs). It validates via a DNS TXT record, so it
needs no inbound `:80`/`:443` reachability and is immune to edge interception. Shape: a
custom Caddy build carrying the provider's [libdns](https://github.com/libdns) module, plus
a scoped DNS-API token delivered as a Steward secret. With a valid origin cert, the CDN runs
in **Full (strict)** mode — the recommended secure topology.

**The tension (worth naming):** the obvious DNS-01 target is Cloudflare, and wiring it in
deepens our dependence on a large US corporation — against Agora's "make capture expensive"
and operator-ownership grain (`decisions/borrowed-substrate.md`,
`decisions/licensing.md`). So build it **provider-agnostic** (libdns already is) and prefer
aligned providers. Candidates for future work — evaluate libdns support + token scoping when
picked up:

- **DNS hosting (for DNS-01):**
  - **deSEC** (desec.io) — non-profit, free, privacy-focused, open API, has a libdns module.
    The most Agora-aligned pick.
  - **Hetzner DNS** — already in the stack (the boxes run on Hetzner), EU, has an API + libdns.
  - **Self-hosted authoritative** (PowerDNS / Knot, via their libdns modules) — most
    sovereign, heaviest ops (you run redundant nameservers). The "own it outright" option.
  - *(Cloudflare stays supported as one option, never the only one.)*
- **Edge / CDN (the orange-cloud function — DDoS, hiding origin IP):** usually **not needed**
  — Caddy on the box terminates TLS and serves directly, which is the most aligned (own your
  edge). When a CDN is genuinely wanted, **bunny.net** (small, EU, transparent pricing) over
  the megacorps.
- **Tunnels (reaching a NAT'd box):** **headscale** (self-hosted Tailscale control plane) >
  Tailscale > Cloudflare Tunnel — see *Remote reach for Dispatcher* below.

## Litestream for app SQLite databases

The backup engine is built and settled ([`backup.md`](../backup.md)). What is left open
is the complement to it: **continuous replication for mutable app databases**
(Steward Console-on-box, SQLite apps), where restic's snapshots leave a window. Not the
record — that is append-only, and belongs to Off-host shipping above.

## Secret handling — the slices after the first

Declarative deploy is built and settled ([`declarative-deploy.md`](../declarative-deploy.md),
contract in [deploy.md](../../blueprint/steward/deploy.md)). Two slices remain:

- **`secret ls` / `secret rm` + `status` surfacing** (names only, never values).
- **Encrypted-at-rest store driver** (`pass`/`shell`) — lands with god-key custody;
  changes the at-rest defense, not the deploy contract. Would also wrap
  `/var/lib/steward/secrets/` (the restic password).

The console's Environment panel is in
[console-open-questions.md](console-open-questions.md); the higher-level frame — what a
deployable app *is*, and the hooks question — is in
[deploy-config-model.md](deploy-config-model.md).

## Rescheduling the maintenance window

Reading it is built — `status` reports the unattended-upgrades window and pending updates,
and the machine page shows "Maintenance — daily at HH:MM" with an Apply Now. **Changing the
time is open.** It needs
a `steward maintenance --at HH:MM [--reboot on|off]` operate command that rewrites
`/etc/apt/apt.conf.d/52-harden-unattended` — a **root-owned** file, so it needs the narrow
`sudoers.d/steward` pattern (same as `apply-updates`), recorded + witnessed. A *forced reboot
now* would also bump the **no machine-reboot command** gap (kept off the surface for v1:
"apply now" patches now; reboot stays on the schedule).

## Registry credential helpers — short-lived tokens

Static registry credentials are built and settled
([`registry-credentials.md`](../registry-credentials.md)). What is open:

- **Credential helpers for short-lived-token registries** (AWS ECR ~12h, GCP Artifact
  Registry). A static `auth.json` rots; these expect `docker-credential-*` helpers — a
  different mechanism. v1 is static credentials only. Doctor's coverage check partly
  mitigates (a rotted token reads as "not logged in"), but a *present-but-expired* static
  token still passes presence — an optional per-registry auth probe could close that.
- **Steward Console side**: a recorded login/logout ceremony + an Access-style credentials
  ledger on the machine page (#16-adjacent), plus the derived "image is on a registry the
  box isn't logged into" warning. Tracked in
  [console-open-questions.md](console-open-questions.md).

## Health gate is HTTP-only — TCP/exec mode for non-HTTP services

`waitHealthy` does an HTTP `GET` on the deploy port, so an app must speak HTTP to pass
the gate. Pure-TCP services (Postgres :5432, Redis :6379) never go healthy and the deploy
fails — they're excluded from the demo library for this reason. A second health mode would
admit them: a **TCP connect** check (port opens) or an **exec** check (run a command in the
container, e.g. `pg_isready` / `redis-cli ping`). Surfaced while authoring
`examples/library.yml`. Folds into [deploy.md](../../blueprint/steward/deploy.md) once
chosen.

These pure-TCP services are also exactly the **accessories** an app runs alongside it — so
this health mode is a prerequisite for the accessory model below.

## Accessories — multi-container apps on a shared network

**In scope (decided 2026-06-24) — build toward this.** The model below is settled; what remains is
the design + build. Accessories land as a new `accessories` block **inside the AppConfig artifact**
(so they version with the config — see
[`app-config-is-the-artifact.md`](../app-config-is-the-artifact.md)), rendered as their own Quadlet
units on a shared network with stable aliases.

Every app today is **one container** behind Caddy: `deploy` publishes it to a loopback port
(`PublishPort=127.0.0.1:<port>:<port>` in `quadlet.go`) and Caddy routes there. There is no
way to run an app *with* a companion service — a Rails app that needs Redis or Postgres, the
common case. Kamal calls these **accessories**. The deploy spec
([deploy-config-model.md](deploy-config-model.md)) has no field for "this app also needs these
services," and nothing on the box yet lets one container reach another by name — the two gaps the
model below closes.

**The model (mapped from Kamal/Compose, which we already treat as inspiration —
[`borrowed-substrate.md`](../borrowed-substrate.md)):** a **shared user-defined Podman
network** that Steward creates-if-not-exists before attaching anything. The app container,
its accessories, and Caddy all join it. On a user-defined network Podman's **aardvark-dns**
(the netavark backend's resolver) gives container-to-container name resolution — the same
"reach `redis` by hostname" that Compose and Kamal 2 rely on. Accessories boot with stable
names; the app's connection string points at the name; Caddy joins the network for the same
reason kamal-proxy must live on the kamal network — to route to the app. Accessories are
separate, long-lived containers, **not** a Podman pod: a pod shares one netns (reach on
`localhost:port`) but couples lifecycles, and we want accessories to **outlive app
redeploys** — so shared-network-separate-containers is the right analog, not co-location.

**Two walls to design around:**

1. **Rootless DNS is not guaranteed present.** Steward runs as the unprivileged `steward`
   user, and rootless container-to-container DNS works *only* if **aardvark-dns is installed
   and netavark is the backend**. On a stripped-down server the DNS helper is sometimes
   missing — and then names silently fail to resolve while IPs still work, which looks exactly
   like a bug. So `prepare` must install/verify aardvark-dns and `doctor` must **check it is
   present** (a real verify step, like the existing Podman ≥ 4.4 assert), never assume it.
   Folds into [provision.md](../../blueprint/steward/provision.md).

2. **Discovery must not ride a churning container name.** Kamal hands accessories a clean
   `<service>-<accessory>` name but suffixes role/server containers with a digest, which makes
   them unreachable by a predictable name — fixed with an explicit **network-alias**. We carry
   the same hazard already: blue/green names every app container `<name>-a` / `-b` (`otherColor`
   in `quadlet.go`), and any digest/tag in a name would churn every deploy. **Rule: every
   container something else reaches by name gets a deliberate, digest-free network-alias** (e.g.
   `console-redis`) that stays constant across redeploys; connection strings point at the
   alias, never the container name. The digest/color can churn; the alias is the stable contract.

**Lifecycle:** the network and the accessories **persist across app redeploys** — don't tear
the network down or reap an accessory on app churn (they're shared and longer-lived, like the
registry login). This makes accessories the natural home for the **pure-TCP services** the
HTTP-only health gate currently excludes (Redis, Postgres — see above): an accessory wants the
TCP/exec health mode, not an HTTP `GET`. Where it lands: a new `accessories` block in the
deploy envelope (the missing axis in [deploy-config-model.md](deploy-config-model.md)'s "what's
in App Config"), rendered as their own Quadlet `.container` units on the shared network with
stable aliases. Folds into [deploy.md](../../blueprint/steward/deploy.md) once designed.

## apt packaging — the inert-package / prepare split

Steward mostly follows Linux convention already (state in `/var/lib/steward`,
validated `sudoers.d` drop-in, system user + subuid/subgid, static signed binary);
a man page now generates from the commands table (`make man`). What a `.deb` would
change, and the design insight worth keeping when this is picked up:

> **apt puts bits on disk; `prepare` stays the accountable act that turns them on.**

The package apps an *inert* Steward — binary (`/usr/bin`, not `/usr/local`),
units shipped in `/usr/lib/systemd/system` (disabled), the `steward` user via
postinst, deps declared not installed (`Depends: podman (>= 4.4), uidmap`;
`Recommends: restic`; **caddy availability varies by release — verify, else it
stays a prepare step**). `prepare` shrinks to the recorded root ceremony: lay the
floor, configure Caddy routing, enable the timer. Its current `apt-get app`
steps stay for the curl-install path (already idempotent).

**Interaction with the recorded binary digest** ([`roles-not-packs.md`](../roles-not-packs.md)):
`prepare` writes this binary's sha256 to `/etc/steward/binary.digest`, and every verb that
acts checks the running binary against it — so an `apt upgrade` that replaces the binary
leaves the box refusing every deploy until `prepare` is re-run. Curl-install has the same
property and the same fix (the upgrade path already says "then `steward prepare`"), but a
package manager upgrades unattended, which makes it sharper: the box would go quiet without
anyone having typed anything. Options when this is picked up: a postinst that re-records
the digest through the core (so the authorization lands in the chain rather than in a
packaging script), or accepting the refusal as the correct fail-closed outcome and making
`doctor` say exactly this. **The refusal must not be softened into a warning** — a binary
nobody authorized running deploys is the thing the check exists to stop.

Mapping that must hold: `apt remove` ≈ `steward uninstall`, `apt purge` ≈ the
hardware-retirement tier (see Decommissioning above) — with the caveat that a
conventional `postrm purge` deleting `/var/lib/steward` would shred the record;
purge should archive-or-warn instead (Agora II).

Also needed: `debian/` (control, rules, DEP-5 copyright, changelog), vendored Go
deps for offline build, version `0.1.5beta` → `0.1.5~beta` (`~` sorts before
release). Distribution in two tiers, in order: **self-hosted signed apt repo**
(aptly/reprepro on the release host — the boring long-term answer to curl|bash),
then Debian proper (ITP, sponsor) only once the surface is stable.

## Time-boxed grants — `authorize --expires`

A grant that prunes itself at expiry (a timer removes the `authorized_keys` line) —
Article VI. Would retire the old separate `service-mode` verb. Folds into
[auth.md](../../blueprint/steward/auth.md).

## A self-update scope — an app may redeploy itself

> **Doubt (2026-06-09):** maybe not worth its own scope. Anything with `operate` (e.g. a
> co-located Steward Console) can already update an app, and
> [deploy-config-model.md](deploy-config-model.md) argues there's no structural
> image-vs-config boundary — "self-update" collapses into *which fields of the one config a
> scope may edit*. Kept as a thread, not a plan. The sketch below is the strong form if it
> ever earns its place.

Generalize the "Steward Console deploys Steward Console" POC
([console-open-questions.md](console-open-questions.md)) into a first-class grant:
a scope, narrower than `operate`, that lets a deployed app **redeploy only itself** and
do nothing else. The named actor is the app; the forced command pins both the *verb*
(deploy/rollback) and the *target* (this one app), so the key can push a new image of
itself but can't touch another app, read the record, or open a shell. Sits *below* operate
on the ladder — `observe ⊂ self-update ⊂ operate ⊂ grant` — the smallest useful write.

This is what makes ordinary self-updating apps safe: any app (not just Steward Console) can hold
a key that updates itself, and the blast radius is exactly one install. Mechanism is the
existing `authorize` forced-command path plus a target argument — likely
`authorize <pubkey> --client <app> --scope self-update --app <name>`, decoded in the
`_exec` gate the same way `observe`/`operate` already are. Folds into
[auth.md](../../blueprint/steward/auth.md) and the scope ladder once decided.

Open edges: does "itself" mean the exact `--app` name (rename = new grant), and does the
grant survive the app being removed and redeployed? Pairs naturally with **time-boxed
grants** (a self-update key that expires) and is the per-app counterpart to the coarse
fleet delegation below.

## Per-app isolation on a shared box — scoped observe / image allowlist

The `operate` key is **box-wide** by design: it can `deploy`/`remove`/`status` *any* app
on the box (small, legible ceiling; no notion of "tenant"). So between two Projects
sharing a box, the boundary is **not sharing the box** — which is why Steward Console makes
**dedicated the default** ([install-journeys.md](install-journeys.md)). For that common
case there is **nothing to build here**; the isolation is Steward Console-side query discipline.

The *only* thing that would make per-app isolation **un-bypassable inside a shared box** is
a Steward-side scope:

- **Scoped observe** — a key that can `status`/`record` for **named apps only**, not the
  whole box. The observe analog of the image allowlist; the read-side sibling of the
  per-app **self-update scope** above (which already pins a key to one `--app`).
- **Image allowlist** — the box refuses any image not authorized (the
  [app-library.md](app-library.md) "real teeth" layer).

Same "separate, simple, maybe later" shape as the allowlist, and **dedicated-by-default
makes it rarely necessary** — pick it up only when genuine multi-tenant shared boxes with
mutually-distrusting projects are real. Mechanism would ride the existing `_exec` gate +
a target argument, exactly like self-update.

## Blocking container egress to the metadata service

The rest of this thread is **settled** — see
[`../what-a-container-can-reach.md`](../what-a-container-can-reach.md) and the spec section
it points at. A container cannot reach another app's published port; it *can* reach
`169.254.169.254`, which on Hetzner carries no credentials but does carry cloud-init
user-data.

What stays open is whether to block it. The rule would have to reject only the `steward`
user's traffic to that address: box-wide, it risks cloud-init's network setup on the next
boot, which is a worse failure than the disclosure. Against building it: no credentials are
exposed, and "never put a secret in user-data" is a cheaper rule that holds everywhere.
Revisit if Steward ever runs somewhere whose metadata service hands out credentials (AWS
IMDS being the obvious one), where this stops being information and becomes a key.

## Remote reach — NAT'd boxes

Reaching a NAT'd box with no inbound port: run the scoped SSH *through* a tunnel. SSH
stays the identity and scope; the tunnel only carries it. Not needed for a single-box
operator. Prefer the self-hostable option for Agora alignment: **headscale** (self-hosted
Tailscale control plane) > Tailscale > Cloudflare Tunnel.

## Per-action fleet delegation

At the fleet layer, grants finer than an SSH key can express: attenuable,
time-boxed, offline-verifiable, per-action ("operator Z may deploy image X to box Y,
expires in 5 minutes"). SSH keys are too coarse for this; a capability-token scheme is
the candidate. Revisit when fleet delegation is real, not before.

## An MCP for Steward — its own doc

Handing an AI agent a tool surface over Steward. Nothing planned; the shapes, the one
new threat (prompt injection), and the shapes already forbidden are written up in
[steward-mcp.md](steward-mcp.md). It leans on *time-boxed grants* and *scoped observe*
above, which is why it is flagged from here.

## Security smoke-tests — industry-standard tools

**Mostly built** — see [`decisions/security-audit.md`](../security-audit.md) for the why
and [`audit/log.md`](../../audit/log.md) for the per-version attestation.

- **`govulncheck` + `gosec`** — **wired** as `make audit` (gates `release`). gosec's
  perms/path rules are excluded by policy; G204 stays on, annotated per site.
- **`ssh-audit` + `nmap` + `Lynis`** — **wired** as `make audit-box HOST=…`
  (`audit/run.sh`); run against a prepared+hardened box, fold regressions into `harden/`.
- **`harden --check`** — **built**: a native, dependency-free on-box posture check that
  publishes its result for `status`/Steward Console to read (the everyday guard between deep
  audits).

Still open / deferred:

- **First real run + baseline.** Run `make audit-box` against the devbox, capture the
  baseline (ssh-audit grade, open-port set, Lynis index) and make `audit-box` fail on a
  regression from it. Also: **bump the build toolchain** so `make audit`'s govulncheck is
  clean (the stale Go patch is the current finding).
- **Trivy** — scan the Steward Console image (no image for the Steward binary); pairs with the
  registry/image work, not this.
- **`testssl.sh`** — needs a real cert; rides with the DNS-01 / HTTPS work.
- **OpenSCAP** — rejected for now (compliance machinery, against the grain); Lynis covers
  it lighter. See the decision.

## Further hardening (later)

Carried over from the original draft; none are near-term:

- **Secrets at rest** — age / SOPS for app secrets.
- **God-key custody** — `systemd-creds` / TPM for the root signing/bootstrap key.
- **App unit hardening** — systemd Quadlet for container units plus a default
  `OOMScoreAdjust` are **built** (see [`../quadlet-deploy.md`](../quadlet-deploy.md)).
  What remains is a per-app override (`OOMScoreAdjust`/`MemoryMax` in the deploy spec).

---

> The three threads below came out of a 2026-06-18 review pass. **Suggested topics,
> nothing decided** — raised here so the gaps aren't lost, not endorsed as work.

## Caddy certificate state — does it survive a redeploy?

Caddy auto-manages HTTPS (ACME/Let's Encrypt), so the box holds **cert + ACME-account
state** — CertMagic's storage, normally under Caddy's data dir. The open worry: **where
does that live, and does it persist across a Caddy redeploy/reboot?** If it sits in
container-ephemeral space rather than a declared volume, every redeploy re-requests certs
and can trip **Let's Encrypt rate limits** (the failure looks like "HTTPS stopped working"
with no obvious cause). ACME *validation* failure is already noted in
[what-could-go-wrong.md](what-could-go-wrong.md); this is the distinct *persistence* edge.
Likely answer is a named volume for Caddy's data dir that's never pruned — confirm what
the Caddy unit actually mounts, then either document it as covered or add the volume.
Folds into [deploy.md](../../blueprint/steward/deploy.md) / the Caddy unit once checked.

## Time sync — is chrony in the base image?

TLS validity windows and **audit-log timestamps** (cross-box correlation in the record)
both assume the box clock is right. Steward's auth is scoped SSH, not bearer tokens, so
there's **no token-skew dependency** — but a drifting clock still silently breaks cert
validation and makes audit timestamps useless for ordering events across the fleet. Open:
is **chrony** (or `systemd-timesyncd`) enabled as part of `prepare`/`harden`, and should
`doctor` assert the clock is synced (the same shape as the existing Podman/aardvark-dns
checks)? Cheap to add, easy to forget. Folds into
[provision.md](../../blueprint/steward/provision.md).

## Decommissioning a retired box — the remaining hardware-retirement gap

**The common case is built:** `steward uninstall` (root ceiling) removes the gate and
the scribe — timer, ledger, sudoers grant, binary — keeps apps running by default
(explicit opt-in removes them, as the steward user), keeps the record, and surfaces
the restic repo + password on the way out. Spec in
[provision.md](../../blueprint/steward/provision.md); why in
[`uninstall-removes-the-gate.md`](../uninstall-removes-the-gate.md).

What remains open is **hardware retirement** (sold, returned, wiped): shredding
`/var/lib/steward/secrets/` and the podman secret store, removing the `steward` user,
deciding the record's fate (archive off-box first?), and the **restic repo** decision
(the encrypted backups outlive the box — keep or destroy). Deliberately not bundled
into uninstall so the reversible act doesn't carry the irreversible one. Shape open:
extend uninstall with a `--wipe` tier vs. a separate recorded checklist. Pairs with
the Access (#16) grant-scope work already flagged in journeys.

## Is "run on the box" provable from the record?

**Raised 2026-09-30**, building the record's stamps. The console marks a box entry *on
the box itself* when its actor is `operator` — the name `core.ActorName` gives any local
invocation. Two ways that name misleads:

- **Anything local that does not name itself gets it.** The snapshot timer did, so a box
  whose timer was refused once a minute read as someone typing the same command once a
  minute. *Fixed:* the timer now runs as `snapshot-timer`. The console's label was also
  softened from "run by hand" to "on the box itself", which stays true for any local run.
- **`authorize` accepts `operator` as a client name**, so a scoped key could be named that
  and its acts would read as local. *Open.* Two boring fixes: reserve `operator` in
  `validClient`, or record the door on the entry itself (`via: shell|ssh`), a
  record-format change ([`../record-format.md`](../record-format.md)). Reserving the name
  is smaller; recording the door is the stronger claim.
