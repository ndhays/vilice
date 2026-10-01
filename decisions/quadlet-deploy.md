# Quadlet app deploy — why (settled)

> The deploy rearchitecture: app containers are **systemd Quadlet units**, deployed
> **blue/green**, drained by the **app itself**. **Shipped** (both slices); the canonical
> behavior lives in [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md) and
> [`provision.md`](../blueprint/vilice/provision.md). This records the *why* and the roads
> not taken. Graduated from `decisions/open/` 2026-06-11 (the one residual question — per-app
> `MemoryMax`/`OOMScoreAdjust` overrides — moved to `open/vilice-open-questions.md`).

**Last touched:** 2026-06-11.

---

## Why Quadlet

Today an app is a bare `podman run` container that Steward starts, renames, and points
Caddy at. That leaves three gaps and blocks two open items — and Quadlet closes all of
them at once, which is why it's the convergence point, not just one fix:

- **Reboot persistence** — a `podman run` container doesn't come back after a reboot.
- **Crash-restart** — nothing supervises a crashed container.
- **Stable routing** — the loopback port isn't pinned, so a restart can break the
  Caddyfile.
- (open) **OOM protection** — no way to tell the kernel "don't kill the control plane
  first."
- (open) **Resource limits** — no `MemoryMax` etc.

Each app becomes a `.container` unit in `/etc/containers/systemd/`; `systemctl
daemon-reload` turns it into a real `.service` that systemd starts on boot, restarts on
crash, and can carry `OOMScoreAdjust=` / `MemoryMax=`. Our Podman secrets carry over
directly (`Secret=name,type=env,target=VAR`), volumes too (`Volume=…:U`), and the port is
pinned in the unit (`PublishPort=127.0.0.1:<hp>:<cp>`) so a restart reuses it and the
Caddyfile stays valid. **Caddy stays the edge**; Steward still flips its reverse-proxy
target. **app-state stays authoritative** — the unit file is *generated* from it, never
hand-edited, so there's no drift.

This is consistent with prior decisions: [`borrowed-substrate.md`](borrowed-substrate.md)
already lists **systemd** as a chosen substrate and already rejected Kamal-as-engine.
Quadlet just leans harder on the systemd we already committed to; we keep owning the
wide-but-shallow orchestration.

## Locked decisions (the forks)

1. **Blue/green, not in-place `systemctl restart`.** Today's safety property is "a failed
   deploy leaves the running app untouched." systemd has no native canary, and an in-place
   restart stops the old unit before starting the new — if the new fails, you're *down*.
   So we alternate colors `<app>-a` / `<app>-b`: write the inactive color's unit with the
   new image and a fresh port, start it, health-check, flip Caddy, then retire the old
   color. A failed health check just tears down the new color; the old keeps serving.
   This also makes the stable-port question moot — each color pins its own port, and the
   live one persists across reboot.

2. **Rootless user units from the start** *(revised 2026-06-08, after
   `decisions/ceiling-is-the-machine.md`).* The earlier "rootful now" is dead: `deploy`,
   `start`, `stop`, `remove` now run as the unprivileged **`steward` user** and refuse
   bare root, so they cannot write `/etc/containers/systemd/` or drive system `systemctl`.
   Units live in **`~steward/.config/containers/systemd/`** and are managed with
   **`systemctl --user`** as `steward`. `prepare` already laid the groundwork —
   subuid/subgid ranges and `loginctl enable-linger steward` (so user units run at boot
   without a login). So Slice A *completes* the container-user-model migration rather than
   deferring it; it must also flip the `steward-snapshot` timer to `User=steward` (and read
   `podman ps` as `steward`) so the recorder sees the now-rootless containers.

3. **App-driven drain — no external probing.** See below. We deliberately rejected a
   fixed timer, host socket-counting (`ss`), *and* polling Caddy's
   `/reverse_proxy/upstreams` `num_requests`. The app's clean exit is the signal.

## Deploy + drain

```
write inactive color's unit (new image, fresh port) to ~steward/.config/containers/systemd/
  → systemctl --user daemon-reload → start <app>-<color> → health-check
  → flip Caddy (new color gets new traffic)
  → SIGTERM old color (systemctl --user stop)
  → old app drains: stop accepting, finish in-flight HTTP, send websocket 1001
    "going away" close frames, then exit
  → bounded by TimeoutStopSec (default 30s — the lone knob)
  → remove old color's unit file → daemon-reload
```

(All `systemctl` calls are `--user`, run as the `steward` user.)

**Why app-driven, not external.** Steward is daemonless — there's no resident process for
an app to call, so the channel must be pull/observe, not push. The systemd lifecycle we're
adopting already gives the right one: the app **drains on SIGTERM and signals "done" by
exiting**, and systemd/Steward observe the state change. The app is the only party that
knows its own connection semantics (especially websockets), so making it authoritative is
strictly more correct than any probe Caddy or the host can run.

- **`num_requests`/`ss` rejected** because both count a websocket as perpetually active —
  they never reach zero for a ws app, so you hit the timeout anyway and *still* need the
  app to close gracefully. The external signal adds coupling (Caddy admin API surface, or
  noisy raw-socket counts that include idle keep-alives) for no win once the app owns the
  drain.
- **Websockets cannot be migrated** across container instances by anyone (not Caddy, not
  kamal-proxy). The best achievable is a *clean reconnect*: the app sends `1001` and the
  client reconnects onto the new color via Caddy. So a deploy always reconnects ws clients
  — gracefully if the app cooperates, abruptly (cut at the timeout) if it doesn't.

### Custom long-drains: `sd_notify`, hand-written

An app that needs longer than the default can use the systemd notify protocol — **written
directly in code, no library/gem dependency** (it's a datagram write to `$NOTIFY_SOCKET`):

- `EXTEND_TIMEOUT_USEC=…` — extend its own grace while it finishes draining, **capped** by
  Steward so a stuck app can't extend forever.
- `STOPPING=1` on entry to drain.
- clean exit = done.

(An app drain-readiness HTTP endpoint Steward polls is a possible later opt-in for apps
that can't simply exit — not baseline.)

## The app shutdown contract (document for app authors)

On `SIGTERM` an app should: (1) stop accepting new connections, (2) finish in-flight HTTP,
(3) send `1001 "going away"` to any websockets, (4) exit. Apps that ignore SIGTERM get
cut at `TimeoutStopSec` — the degraded, but bounded, fallback. This belongs in
`blueprint/vilice/deploy.md`'s app-contract section **and** in app-author-facing
[`site/content/`](../site/content/) (per "site docs must not lag the code").

## Lifecycle = systemd

A systemd-enabled unit restarts on boot even after a `podman stop`, so lifecycle verbs map
to enable/disable to match operator intent (all `--user`, as `steward`):

- `steward start <app>` → `systemctl --user enable --now`
- `steward stop <app>`  → `systemctl --user disable --now` (stays down across reboot)
- `restart` → `systemctl --user restart`

(With linger enabled, a `--user` enabled unit still starts at boot without a login.)

## Prerequisite

Quadlet needs **Podman ≥ 4.4**. `prepare` / `doctor` assert it (Ubuntu 26.04 is fine).

## Memory & usage note (the 30s window)

Blue/green means both colors are resident during the overlap. **30s is a ceiling, not the
typical** — the app exits as soon as it's drained, so real overlap is usually sub-second;
the full window only bites for slow/ws-heavy drains. It's resource overlap, not downtime
(the new color is already serving). The one real risk is a **deploy-time memory spike** on
a tight box — but deploys are serial, so it's +1 app's RSS transiently, not a doubling of
everything. Mitigation: size host headroom ≥ the largest single app's RSS.
An earlier draft added a second one — raise the **draining** old color's `OOMScoreAdjust`
at SIGTERM so the kernel kills the doomed-anyway color first. It was built, and a live test
on 2026-09-29 showed it had never worked: `OOMScoreAdjust` is a unit's exec-context
property, so systemd applies it at process start and accepts a runtime change only on a
transient unit. `systemctl --user set-property` on a Quadlet unit answers "Cannot set
property OOMScoreAdjust", and the value would not have reached a running process anyway.
The call is **removed**; both colors sit at 100, the control plane at 0. Headroom is the
lever. (Per-color `MemoryMax` is fine; the host must
just hold both colors during overlap — headroom is the lever, not the per-color cap.)

## Supersedes / answers

- `vilice-open-questions.md` → **Gapless cutover** — answered here. Note its premise was
  *overturned*: it said to confirm the Caddy admin-API graceful flip before banking on it;
  we chose app-driven drain instead and do not use the Caddy admin API.
- `vilice-open-questions.md` → **Further hardening → "App unit hardening: systemd
  Quadlet"** — promoted from someday to this active plan.
- `vilice-open-questions.md` → **Container user model** — Slice A **closes** the Podman
  rootless half: units are rootless user units as `steward`, and the `snapshot` timer flips
  to `User=steward`. (The auth half — scoped keys authenticate as `steward` — was already
  settled in `ceiling-is-the-machine.md`.)
- `console-open-questions.md` → **OOM priority** — the Steward half is Slice B's
  `OOMScoreAdjust`; the Steward Console-as-managed-app case rides the same unit mechanism.
