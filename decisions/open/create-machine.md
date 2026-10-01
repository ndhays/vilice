# Vilice Console — Create Machine (automated onboarding)

> The settled bootstrap principle (**Vilice Console is never root; the box self-bootstraps and
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

**Last touched:** 2026-08-14.

---

## Open, and asked first: does provisioning belong *inside the app form*?

Raised 2026-08-14, when the **New box (Hetzner) — coming soon** card was removed from
`apps/new`. That card was a stub in the middle of the built path: choosing it hid the
submit button, so the form's most prominent second option was a dead end. Deleting it is
not a decision about Create Machine; it is a refusal to advertise one.

The question it leaves open is narrower than "should we build an adapter" (that shape is
settled, above). It is: **should Create Machine ever be a branch of the app form, or
only its own act?** The two readings:

- **Its own act.** Boxes are made on the fleet page and arrive at the app form the
  way every other box does — already reachable, already holding an `operate` key. The
  app form keeps one machine question with one kind of answer, and provisioning
  inherits nothing from the app's lifecycle. The seam is the seam we already have.
- **A branch of the install.** "Give me a box and put this on it" is genuinely one
  intention, and splitting it makes the newcomer's first app a two-page errand.
  The cost is the whole `awaiting_machine → ready` machinery below — an app that
  must survive minutes of async, resume after a crash, and surface a provisioning
  failure without hanging — plus a form that behaves differently depending on a choice
  made three fields earlier.

The bias is **the first**, on the project's usual grounds: it is the boring option, it
removes a failure mode rather than handling one, and the async lifecycle is a large
mechanism bought entirely to serve one branch of one form. Worth deciding **before** the
adapter is built, because the answer changes what the adapter has to promise: a
standalone act can be synchronous-with-polling on its own page, while an in-form branch
forces the app states.

Not settled. When it settles, it graduates to `decisions/` and the winning shape lands in
[`../../blueprint/console/journeys.md`](../../blueprint/console/journeys.md).

---

## Create Machine — Hetzner / cloud-init

Vilice Console calls a provider's API (Hetzner Cloud first) to provision a server, passing
**cloud-init userdata** that installs Vilice, runs `prepare` (+ `harden`), and
`authorize`s Vilice Console's pubkey at `operate` scope — so the box boots Vilice-ready and
reachable, **zero manual steps, Vilice Console never root** (cloud-init does the local
bootstrap; this satisfies [`../machine-onboarding.md`](../machine-onboarding.md)).

Needs:

- An **encrypted provider token** (a `Setting` / credential), server-type + region pickers.
- **Async provisioning + a "provisioning…" state** — it takes minutes, so the app must
  carry itself across it rather than block (the lifecycle-states question in
  [`install-journeys.md`](install-journeys.md)).
- With **no provider configured**, "New dedicated box" degrades to **emit the cloud-init /
  bootstrap blob to run yourself** — i.e. it falls back to the manual path, never dead-ends.

## Other open edges

- **Scope at bootstrap** — `operate` by default. `ssh` (grant authority) only where you
  want Vilice Console to run the Access ceremony (#16) on that box — recorded per machine in
  `Machine.scope` (extend the enum with `ssh`). See the two-axis note in
  [`../ceiling-is-the-machine.md`](../ceiling-is-the-machine.md).
- **Reachability verify + the "connected" state** after authorize (a `status` round trip
  that writes `last_seen_at`/`status`) — ties to ingestion (#6).
- **Import an existing key** stays an escape hatch, not the path.
