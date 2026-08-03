# Steward Console — Create Machine (automated onboarding)

> The settled bootstrap principle (**Steward Console is never root; the box self-bootstraps and
> authorizes an `operate` key**) graduated to
> [`decisions/machine-onboarding.md`](../machine-onboarding.md); the built **Add Machine**
> flow and the isolation rule are in
> [`blueprint/console/journeys.md`](../../blueprint/console/journeys.md). What remains
> open is the **automated** path.
>
> The *shape* of this is now settled as the **ProviderAdapter** boundary
> ([`../provider-boundary.md`](../provider-boundary.md), canonical in
> [`patterns.md`](../../blueprint/console/patterns.md)): Create Machine = `provision(MachineSpec)
> → the four connection facts`; the linkage on `Machine` is thin and nullable; the core needs
> no adapter (bare-SSH boxes work). What's open here is the **build** of the first adapter.

**Last touched:** 2026-06-18.

---

## Create Machine — Hetzner / cloud-init

Steward Console calls a provider's API (Hetzner Cloud first) to provision a server, passing
**cloud-init userdata** that installs Steward, runs `prepare` (+ `harden`), and
`authorize`s Steward Console's pubkey at `operate` scope — so the box boots Steward-ready and
reachable, **zero manual steps, Steward Console never root** (cloud-init does the local
bootstrap; this satisfies [`../machine-onboarding.md`](../machine-onboarding.md)).

Needs:

- An **encrypted provider token** (a `Setting` / credential), server-type + region pickers.
- **Async provisioning + a "provisioning…" state** — it takes minutes, so the install must
  carry itself across it rather than block (the lifecycle-states question in
  [`install-journeys.md`](install-journeys.md)).
- With **no provider configured**, "New dedicated box" degrades to **emit the cloud-init /
  bootstrap blob to run yourself** — i.e. it falls back to the manual path, never dead-ends.

## Other open edges

- **Scope at bootstrap** — `operate` by default. `ssh` (grant authority) only where you
  want Steward Console to run the Access ceremony (#16) on that box — recorded per machine in
  `Machine.scope` (extend the enum with `ssh`). See the two-axis note in
  [`../ceiling-is-the-machine.md`](../ceiling-is-the-machine.md).
- **Reachability verify + the "connected" state** after authorize (a `status` round trip
  that writes `last_seen_at`/`status`) — ties to ingestion (#6).
- **Import an existing key** stays an escape hatch, not the path.
