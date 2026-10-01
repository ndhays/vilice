# Status Signals — the page is built, the signals behind it weren't

> The Status page ("Now") leads with **exceptions**: apps that are `failed`,
> `unreachable`, or in `drift`, with the boxes behind them. The page and its rollups
> ([`App#state`](../../console/app/models/app.rb)) are built —
> but an audit of what's actually *persisted* found that most of those signals could
> never fire. This is the thread that tracks closing that gap. As each piece settles,
> its truth migrates into `decisions/` (the why) and `blueprint/` (the canonical
> behaviour); this doc keeps the open edges honest.

**Last touched:** 2026-06-17.

The root finding: a live observe read **only warmed the cache** — it never wrote back
the stored projection the Status page reads. So:

- `machine.status` stayed `unknown` forever (never `reachable`/`unreachable`), and
  `last_seen_at` was never stamped → the "Unreachable machines" section could not fire.
- `install_target.current_image` was never populated from a read (only `desired_image`,
  set at deploy) → `drift` could not be detected.
- A failed deploy settles the *Event* `failed` but never marks the `install_target`
  `failed` → the app "failed" rollup stayed latent.

Four threads come out of that, below.

---

## Registry-login in the UI

A private-registry deploy is a near-certain first failure for a real app, and it
classifies cleanly on the box (`registry_auth` / `registry_unreachable` /
`image_not_found` — [`registry-credentials.md`](../registry-credentials.md)). The
Vilice side is **settled**: `registry-login`/`registry-logout` read the secret on
stdin and write a persistent rootless login; `status` lists logged-in registries
redacted.

**The gap is entirely Vilice Console-side:** there is no `Mutation::ACT` for
`registry-login`, no panel to enter credentials, and a `registry_auth` failure surfaces
only as a generic "deploy failed: …" flash — the failure names the fix (`registry-login`)
but the operator can't *do* it in the app.

Open shape:

- Where does it live? A registry is **box state shared across apps**, not an app
  field — so it belongs on the **machine** (an Access-adjacent panel), not the app
  ceremony. It outlives any one app and `remove` must never drop it.
- It's a witnessed act with a **secret on stdin** — the same off-record channel as the
  deploy envelope's secret values. Maps onto the planned secret/env UI (secret by
  default) in [`console-open-questions.md`](console-open-questions.md#secret--env-ui).
- Surfacing: a `registry_auth` deploy failure should deep-link to "log in to
  `<registry>`" rather than just printing the reason.

---

## Deploy ≠ serving — health / DNS / TLS truth

"It deployed" currently doesn't mean "it's serving." After a successful deploy:

- the app may be **unhealthy** (wrong `health` path, app crash-loops);
- the **hostname's DNS** may not point at the box, so Caddy's automatic HTTPS (ACME
  HTTP-01) can't validate and the site doesn't serve;
- a **proxied/orange-cloud** DNS record breaks ACME the same way.

These are the most common real-world "I deployed and nothing's there" cases (see the
user-facing write-up in [`what-could-go-wrong.md`](what-could-go-wrong.md#dns-not-pointing-yet--acme-fails)).
The app row links *out* to `https://<hostname>` but never probes it.

Open shape:

- A post-deploy **reachability probe** (does `<hostname>` answer; did a cert issue?),
  surfaced as app health distinct from "the deploy command returned ok."
- Whether the probe is Vilice Console-side (an HTTP HEAD from the control plane) or a box
  `doctor` check that already knows the local truth (preferred — it can see Caddy's cert
  state). Ties to the "future `doctor`/reachability check" note in
  [`what-could-go-wrong.md`](what-could-go-wrong.md#cloud-provider-firewall-not-just-ufw).
- Needs the `failed`/health signal from thread 1 to land first to have somewhere to show.

---
