# Caddy's admin API is a socket, not a port

> Decided 2026-09-19. Spec:
> [`../blueprint/vilice/provision.md`](../blueprint/vilice/provision.md). Corrects an
> earlier claim that the TCP endpoint was safe because it was loopback-only.

## The problem

Vilice reloads Caddy through its admin API. By default that is TCP on `localhost:2019`
with **no authentication**; its only check is the `Host` header, which a local process
sets freely.

So any local account, and any container that can reach the host's loopback, could replace
the whole config: redirect every domain, forward to any app's loopback port, or serve any
file the caddy user can read, TLS keys included. That broke invariant 3 — *enforced by
ownership, not convention.*

## The decision

The admin API listens on a Unix socket, and file ownership decides who may connect.

| Piece | Setting | Why |
|---|---|---|
| Directory | `/run/caddy-admin`, `caddy:vilice`, `2750` | Only caddy and the vilice group reach the socket. Setgid, so the socket takes that group. |
| Socket | `admin unix//run/caddy-admin/admin.sock\|0220` | Connecting needs write permission; `0220` grants it to owner and group only. |
| Boot | `/etc/tmpfiles.d/caddy-admin.conf` | `/run` is empty after a reboot. |
| Reload | `caddy reload --address unix//run/caddy-admin/admin.sock` | The address is named, so a Caddyfile that lost its `admin` line fails the reload instead of falling back to `:2019`. |
| Check | `doctor`: the socket opens, and nothing answers on `:2019` | Drift is surfaced. |

Written by `prepare` (`configureCaddy`). On a box whose Caddy still listens on TCP,
`prepare` restarts Caddy once instead of reloading, because a reload would dial a socket
that does not exist yet.

Tested against Caddy 2.11.3: the socket takes the directory's group, reload works, and
Caddy starts over a stale socket left by `kill -9`. `systemctl reload caddy` runs as the
caddy user, the socket's owner, so it keeps working.

Caddy is not a root service: the apt package runs it as its own `caddy` user.

## Roads not taken

- **Keep TCP, add authentication.** Caddy's remote admin uses client TLS certificates — a
  CA to run and rotate for a connection that never leaves the box.
- **Put `_vilice` in the `caddy` group.** Hands it read access to everything else that
  group can read. The setgid directory grants the socket and nothing more.
- **A world-writable socket (`0222`) protected by the directory alone.** Works today. The
  socket's own mode carries the rule so `ls -l` tells the whole story and loosening the
  directory would not open it.
- **Turn the admin API off.** Every config change becomes a restart that drops
  connections and needs root.
- **Check it in `harden --check`.** `harden` knows nothing about Vilice or Caddy.
  `doctor` checks it.
