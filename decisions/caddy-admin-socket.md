# Caddy's admin API is a socket, not a port

> Decided 2026-09-19. Caddy's admin API moves from `localhost:2019` to
> `/run/caddy-admin/admin.sock`, and only the caddy user and the `steward` group can open
> it. Corrects an earlier claim that the TCP endpoint was safe because it was
> loopback-only.

## The problem

Steward reloads Caddy through its admin API, which is how a deploy flips traffic with no
root in the loop. By default that API is TCP on `localhost:2019`, and it has **no
authentication**. Its only check is that the `Host` header says localhost, which stops a
browser being tricked into calling it but not a local process, which simply sets the
header.

So "the steward user can reload Caddy" really meant "anyone on the box can". Any local
account, and any container that can reach the host's loopback, could replace the whole
config: send every domain elsewhere, forward traffic to any app's loopback port, or serve
any file the caddy user can read, its TLS keys included. [SECURITY.md](../SECURITY.md)
called this "the one local trust surface", which was accurate, but nothing enforced its
limits. That broke the third invariant: *enforced by ownership, not convention.*

## The decision

The admin API listens on a Unix socket, and filesystem ownership decides who may connect.

| Piece | Setting | Why |
|---|---|---|
| Directory | `/run/caddy-admin`, `caddy:steward`, `2750` | Only caddy and the steward group can even reach the socket. Setgid, so the socket takes the steward group. |
| Socket | `admin unix//run/caddy-admin/admin.sock\|0220` | Connecting needs write permission; `0220` grants it to the owner (caddy) and the group (steward), and nobody else. |
| Boot | `/etc/tmpfiles.d/caddy-admin.conf` | `/run` is empty after a reboot; systemd recreates the directory before Caddy starts. |
| Reload | `caddy reload --address unix//run/caddy-admin/admin.sock` | The address is named, not read from the config, so a Caddyfile that lost its `admin` line fails the reload instead of quietly falling back to `:2019`. |
| Check | `doctor`: the socket opens, and nothing answers on `:2019` | Drift is surfaced, not assumed away. |

Written by `prepare` (see `configureCaddy`) and specified in
[`../blueprint/vilice/provision.md`](../blueprint/vilice/provision.md). On a box whose
Caddy still listens on TCP, `prepare` restarts Caddy once instead of reloading, because
a reload would read the new config and dial a socket that does not exist yet.

Tested against Caddy 2.11.3 before building: the socket takes the setgid directory's
group, reload over it works, and Caddy starts cleanly over a stale socket left by
`kill -9`. The packaged `caddy.service` reload runs as the caddy user, the socket's
owner, so `systemctl reload caddy` keeps working.

## Also corrected

Caddy was described as "a root service". The official apt package runs it as its own
`caddy` user, allowed to bind :80/:443. The blueprint and SECURITY.md now say so.

## Roads not taken

- **Keep TCP, add authentication.** Caddy's remote admin mode authenticates with client
  TLS certificates. That is a certificate authority to run and rotate for a connection
  that never leaves the box. File permissions already answer "who may connect"; a socket
  uses them directly.
- **Put `steward` in the `caddy` group** and let the socket keep Caddy's group. It works,
  but it hands the steward user read access to whatever else the caddy group can read.
  The setgid directory grants the socket and nothing more.
- **A world-writable socket (`0222`) protected by the directory alone.** It would work
  just as well today. The socket's own mode carries the rule instead, so `ls -l` on the
  socket tells the whole story and loosening the directory would not open it.
- **Turn the admin API off** (`admin off`). Then every config change is a restart,
  dropping connections on each deploy, and reload needs root. Blue/green without
  interruption depends on the reload.
- **Check it in `harden --check`.** `harden` is deliberately generic and knows nothing
  about Steward or Caddy. The socket is this layer's setup, so `doctor`, which runs as
  the steward user, checks it.
