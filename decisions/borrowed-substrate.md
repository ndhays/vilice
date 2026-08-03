# Borrow the deep parts; own the shallow glue

**Decided 2026-06-02.**

The dangerous-and-deep work is delegated to mature, purpose-built tools. Steward's own
code is confined to the wide-but-shallow orchestration.

| Concern | Borrowed from |
|---|---|
| Auth + transport | **OpenSSH** — scoped keys + forced commands |
| SSL + cutover (the proxy) | **Caddy** |
| Containers | **Podman** (root today; rootless is the target) |
| Residency + timers | **systemd** |
| Tamper-evident record / off-host shipping | SQLite + a streaming-replication tool *(still open)* |

The point: the only deep surface that is genuinely ours to get right is the
forced-command gate, and OpenSSH carries the hard part of even that.

## Road not taken: Kamal as the deploy engine

An earlier sketch (`switchyard-platform/blueprint/horizon3.md`) proposed making Steward
an un-bypassable membrane in front of **Kamal**. Rejected:

- Kamal's deep value — cert provisioning, gapless proxy — is **Caddy's** job here.
- Kamal's config/repo model fights Steward's "deploy an image from a scoped request"
  model.
- With the deep parts borrowed, deployment orchestration is wide-not-deep — safe to
  own directly.

Kamal stays as *inspiration*, not a dependency. The membrane principle from horizon3
(accountability as a property of the gate, not the engine) still stands; only its
"Kamal engine" conclusion was dropped.

## Reasoning trail

The thinking evolved across `switchyard-platform/blueprint/horizon{,2,3}.md`:
structure (four layers → two programs) → interface (read the dump, run the named-actor
CLI over scoped SSH) → this borrow-the-right-tools flip. Kept as the "why" behind the
shape; the canonical *what* lives in `blueprint/`.
