# Connection limits go in nftables, not in Caddy

> Decided 2026-10-22. **Not built.** What is still open is in
> [`open/vilice-open-questions.md`](open/vilice-open-questions.md#per-address-connection-limits).

## The question

Should Vilice's proxy limit how hard one client can hit the box? Caddy is the edge on
every box, so it looks like the natural place for that.

## The decision

**If Vilice limits anything, it limits connections per source address, in nftables, before
traffic reaches Caddy.** Two rules on 80/443: a rate of new connections per address, and a
cap on open connections per address. Limiting requests per endpoint or per user is the
app's job (Rack::Attack and the like), because only the app knows what a request costs and
who sent it.

## Why not Caddy

- **It is not in Caddy.** The standard build has no rate limiter. The usual one,
  `github.com/mholt/caddy-ratelimit`, is a non-standard module the README calls a work in
  progress.
- **A module means a custom binary.** Vilice installs the stock apt package
  (`installCaddy`). A module means building Caddy or fetching a build from caddyserver.com
  during `prepare`, holding the apt package, and shipping every Caddy security fix ourselves.
  Caddy terminates TLS for the open internet; it is the last component whose updates should
  slow down. That stops borrowing the deep part
  ([`borrowed-substrate.md`](borrowed-substrate.md)) and starts maintaining it.
- **One limit per hostname is the wrong shape.** `/login` wants a few requests a minute;
  static files want thousands. A proxy-wide limit is either too loose to matter or tight
  enough to break pages.

## Why nftables

- **Native.** It is the kernel's firewall, already on the box (ufw is built on it). No new
  package, no custom build.
- **Cheaper.** A flood is dropped in the kernel, before a TLS handshake or a Caddy goroutine.
- **The rules carry no app knowledge.** A per-address connection limit is the same for
  every app, so it needs no spec field.

## What it does not cover

- **Volumetric floods** fill the network link before any rule on the box runs. That is the
  provider's or a CDN's job.
- **Distributed attacks** use many addresses and stay under any per-address limit.

## Roads not taken

- **`caddy-ratelimit` via `xcaddy` or `caddy add-package`.** Above.
- **Per-app limits in the deploy spec, rendered into the Caddy block.** Same binary problem,
  and a blunt limit an app would usually be better off doing itself.
- **fail2ban on Caddy's access log.** Reacts after the requests have been served, and turns
  a log format into a firewall input.
- **Doing nothing.** Reasonable today; this records where a limit goes when one is wanted,
  so the Caddy module is not proposed again.
