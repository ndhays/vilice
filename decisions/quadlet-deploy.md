# Quadlet app deploy

> Decided 2026-06-11, shipped. Spec:
> [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md) and
> [`provision.md`](../blueprint/vilice/provision.md).

## Why Quadlet

An app was a bare `podman run` container. That left it without reboot persistence,
crash-restart, a pinned port, OOM priority, or resource limits. A Quadlet `.container`
unit gives all five: systemd starts it on boot, restarts it on crash, and carries
`OOMScoreAdjust=` / `MemoryMax=`. Podman secrets (`Secret=name,type=env,target=VAR`) and
volumes carry over, and `PublishPort=127.0.0.1:<hp>:<cp>` pins the port.

Caddy stays the edge. **App state stays authoritative:** the unit file is generated from
it and never hand-edited.

## The three forks

1. **Blue/green, not in-place restart.** An in-place restart stops the old unit before
   starting the new; if the new one fails, the app is down. Colors `<app>-a` / `<app>-b`
   alternate: write the inactive color's unit with the new image and a fresh port, start
   it, health-check, flip Caddy, retire the old color. A failed health check tears down
   only the new color. *(Amended 2026-10-22: an app that cannot run beside itself
   declares `stop_first` and takes the in-place trade, with the old color restarted on
   failure — [`stop-first.md`](stop-first.md).)*
2. **Rootless user units.** Deploy and lifecycle run as `_vilice`
   ([`ceiling-is-the-machine.md`](ceiling-is-the-machine.md)), so units live in
   `~_vilice/.config/containers/systemd/` under `systemctl --user`. `prepare` sets
   subuid/subgid ranges and `loginctl enable-linger`, so they start at boot without a
   login.
3. **App-driven drain.** Below.

## Deploy and drain

```
write inactive color's unit (new image, fresh port)
  → systemctl --user daemon-reload → start <app>-<color> → health-check
  → flip Caddy
  → SIGTERM old color (systemctl --user stop)
  → old app drains: stop accepting, finish in-flight HTTP, send websocket 1001, exit
  → bounded by TimeoutStopSec (default 30s)
  → remove old color's unit file → daemon-reload
```

**Why the app drives it.** Vilice has no resident process for an app to call. The app
drains on SIGTERM and signals "done" by exiting. It is the only party that knows its own
connection semantics.

**The app shutdown contract:** on `SIGTERM`, stop accepting connections, finish in-flight
HTTP, send `1001 "going away"` to websockets, exit. An app that ignores SIGTERM is cut at
`TimeoutStopSec`.

An app that needs longer can speak `sd_notify` directly (a datagram to `$NOTIFY_SOCKET`,
no library): `STOPPING=1`, and `EXTEND_TIMEOUT_USEC=…`, capped by Vilice so a stuck app
cannot extend forever.

Websockets cannot be migrated across containers by anyone. The best case is a clean
reconnect onto the new color.

## Lifecycle is systemd

An enabled unit restarts on boot even after a stop, so the verbs map to enable/disable:

- `start` → `systemctl --user enable --now`
- `stop` → `systemctl --user disable --now` (stays down across reboot)
- `restart` → `systemctl --user restart`

Quadlet needs **Podman ≥ 4.4**; `prepare` and `doctor` assert it.

## Memory during the overlap

Both colors are resident during the drain. 30s is the ceiling; the app usually exits in
under a second. Deploys are serial, so the spike is one app's RSS. **Size host headroom
for the largest single app.**

## Roads not taken

- **A fixed drain timer.** The app knows when it is done.
- **Count connections from outside** — host sockets (`ss`) or Caddy's
  `/reverse_proxy/upstreams` `num_requests`. Both count a websocket as active forever, so
  they never reach zero and you still need the app to close.
- **Raise the draining color's `OOMScoreAdjust` at SIGTERM**, so the kernel kills it
  first. Built, and a live test on 2026-09-29 showed it never worked: it is an
  exec-context property applied at process start, and `systemctl --user set-property` on
  a Quadlet unit answers "Cannot set property OOMScoreAdjust". Removed. Both colors sit at
  100, the control plane at 0.
- **Rootful units in `/etc/containers/systemd/`.** The first plan, dead once deploy ran
  as `_vilice`.
- **Flip traffic gracefully through Caddy's admin API alone.** Replaced by app-driven
  drain.
- **An HTTP drain-readiness endpoint Vilice polls.** A possible later opt-in for apps
  that cannot simply exit.

## Still open

Per-app `MemoryMax`/`OOMScoreAdjust` overrides, in
[`open/vilice-open-questions.md`](open/vilice-open-questions.md).
