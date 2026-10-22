# Borrow the deep parts; own the shallow glue

> Decided 2026-06-02.

Deep, dangerous work is delegated to mature tools. Vilice's own code is wide and shallow.

| Concern | Borrowed from |
|---|---|
| Auth + transport | **OpenSSH** — scoped keys + forced commands |
| TLS + cutover (the proxy) | **Caddy** |
| Containers | **Podman**, rootless |
| Residency + timers | **systemd** |
| Backup | **restic** ([`backup.md`](backup.md)) |

The only deep surface that is ours is the forced-command gate, and OpenSSH carries the
hard part of that.

## Road not taken: Kamal as the deploy engine

An earlier sketch put Vilice in front of Kamal as an un-bypassable membrane. Rejected:

- Kamal's deep value — certificates, gapless proxy — is Caddy's job here.
- Kamal's config/repo model fights "deploy an image from a scoped request".
- With the deep parts borrowed, deploy orchestration is safe to own.

What survives from that sketch: accountability is a property of the gate, not the engine.
