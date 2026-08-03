---
title: Packs
---
# Packs

**Contents:** [How Packs Work](#how-packs-work) &middot; [steward-app](#steward-app) &middot; [AppConfig](#appconfig) &middot; [The Catalog](#the-catalog)

Steward is two layers in one binary. A small **core** owns the gate, the record, and the
root ceiling. Everything a box actually *does* — deploy an app, take a backup, tail a log —
lives in a **pack** the core dispatches to.

The split exists so the core can be finished. It is the part you have to trust, so it
should be small, audited, and boring; packs can change at product speed without touching
it.

## How Packs Work

A pack contributes verbs. It gets no privilege of its own: every verb it adds arrives
through the same door, with the account gate applied and the record written first.

Two root-owned paths decide what may run:

```
/usr/libexec/steward/          the shelf — where pack binaries live
/etc/steward/packs.manifest    the manifest — which packs may run, at which digest
```

**The directory locates; the manifest authorizes.** A binary sitting on the shelf with the
wrong hash is refused exactly like one that isn't there. `steward prepare` writes the
manifest and **records each authorization in the chain**, so *what code was ever allowed to
run on this box, and when* is a question the record answers.

Neither path is configurable. A knob that redirects discovery would reintroduce everything
wrong with resolving plugins through `$PATH` — a search path anything can write to is a way
to run code under Steward's name, logged in the chain under an innocent verb.

Packs are named for **what they promise**, not for what they use: `steward-backup`, never
`steward-restic`. The tool underneath can change; the name in every `authorized_keys` file
and every audit chain cannot.

## steward-app

**Built.** The founding pack: running apps on a box and keeping them running.

| Verbs | Scope |
|---|---|
| `deploy` `rollback` `start` `stop` `restart` `remove` | operate |
| `backup` `restore` | operate |
| `registry-login` `registry-logout` | operate |
| `status` `logs` `doctor` | observe |

It deploys from a digest-pinned image into a rootless container, health-checks the new
copy, and flips traffic only once it answers — so a bad deploy never takes the old one
down. Command reference: [Documentation](/index.html#steward-commands).

It installs and drives its own substrate — these are the pack's dependencies, not the
box's. A machine running no app pack needs none of them:

- **[Podman](https://podman.io)** — rootless containers, as ordinary systemd units
- **[Caddy](https://caddyserver.com)** — hostname routing, automatic HTTPS
- **[restic](https://restic.net)** — encrypted, deduplicated backups

Everything it writes is the underlying tool's own plain config file, readable by an admin
who has never heard of Steward.

## AppConfig

An AppConfig is one document that says what an app is — its code, its config, its data, its
secrets. One app should need one document, not a pile of objects spread across a cluster
scheduler. **The config *is* the app.**

It is **values plus references**. A value is inline: a hostname, a port. A reference points
at something kept apart because it is immutable, heavy, or secret:

- **image** points at the **code** — immutable, pinned by content digest, kept in a registry.
- **volume** points at the **data** — heavy and mutable, on disk, surviving every deploy.
- **secret** points at a **sensitive value** — kept off the record, in the box's secret store.

Steward converges one box to one AppConfig. The image is just a field, so *"update the
code"* and *"change the config"* stay separate, separately-recorded acts. Every deploy
records the config **by digest**: one digest is one set of values, forever.

Here is one — the AppConfig for Steward Console itself:

```jsonc
// console.json — the desired state, recorded by digest on every deploy
{
  "image":     "ghcr.io/agoraforge/steward-console@sha256:…",
  "hostnames": ["console.example"],
  "port":      4000,
  "health":    "/up",
  "env":       { "HTTP_PORT": "4000" },
  "secrets":   ["RAILS_MASTER_KEY"],
  "volumes":   ["steward-console-storage:/rails/storage"]
}
```

### Spec

| Field | Type | Required | Description |
|---|---|---|---|
| `image` | string | yes | The container image, **digest-pinned** (`name@sha256:…`). Tags aren't stable; the digest is the code's identity. |
| `hostnames` | string[] | yes | The hostnames Caddy routes to this app. TLS is issued automatically. Each must be a site address — `app.example.com`, `http://app.example.com`, `*.example.com`, or `host:port`. |
| `port` | number | yes | The port the app listens on inside its container. |
| `health` | string | no | HTTP path Steward probes before sending traffic. Defaults to root `/`. |
| `env` | object | no | Non-secret environment, as key/value pairs. Recorded in the clear. |
| `secrets` | string[] | no | **Names** of secrets the box injects as env. Values are supplied at deploy and **never recorded** — see below. |
| `volumes` | string[] | no | Volume mounts, `name:/path/in/container`. The **declaration**, not the data; volumes survive redeploys. A host path instead of a name is a bind mount, and must live under `/srv`. |

**Secrets are names here, values at deploy.** The AppConfig lists only the *names* of its
secrets. The values ride a separate channel at deploy time, over stdin, so they stay out of
the recorded command line and out of the config. Steward puts each value in its Podman
secret store and injects it as container env.

## The Catalog

One pack exists. The rest are the shape of what packs are *for* — listed so the boundary is
legible, not because they are coming soon.

| Pack | What it would promise | Status |
|---|---|---|
| **steward-app** | Apps deployed, routed, health-checked, recoverable. | **Built** |
| **steward-backup** | Backups happen, and can be restored. Splits out of `steward-app` when it has substrate of its own. | Planned |
| **steward-diag** | Observe-scope reads: logs, health, disk, unit status. The pack you hand someone who may look and provably cannot touch. | Planned |
| **steward-cron** | Scheduled jobs as systemd timers, where setting the schedule is itself a recorded act — *who set the job that ran at 3am* becomes answerable. | Idea |
| **steward-db** | Managed Postgres: provision, migrate, snapshot. Migrations are the interesting receipt. | Idea |
| **steward-mcp** | The verb surface as MCP tools, so an AI agent drives Steward natively and every tool call lands in the chain like any other actor. | Idea |
| **steward-static** | A static site — minutes, a newsletter — with the same accountability as an app. | Idea |

Note what is **not** on this list and never will be: `verify`, `authorize`, `prepare`,
`harden`. The commands that constitute the trust model cannot be packs, or the trust model
would have a plugin interface — and the whole design is that it does not.
