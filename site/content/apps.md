---
nav: apps
title: Apps
---
# Apps

**Contents:** [What An App Is](#what-an-app-is) &middot; [AppConfig](#appconfig) &middot; [Spec](#spec) &middot; [The Substrate](#the-substrate)

Steward hosts web applications on a Linux server. A box says what it is for when you
prepare it — `host` runs apps, `balancer` fronts other boxes and runs none — and what
gets installed follows from that. Everything below is about a `host`.

## What An App Is

An app on Steward is a container image, a hostname, and a document that says how they go
together. Nothing else: no cluster, no scheduler, no controller loop.

`steward deploy` pulls the image, brings the new container up alongside the one already
serving, polls it until it answers healthy, and only then moves traffic across. If it
never answers, the old app is left running and the deploy fails — a bad image costs you
an error message, not an outage. The image that was serving is remembered as last-good,
so [`steward rollback`](/commands/rollback.html) is always available.

Images are **digest-pinned** (`ref@sha256:…`). A tag is refused, because a tag is not a
thing you can redeploy: it means something different tomorrow, and *"the image that was
running"* has to be an answer.

Every verb has its own page: [the command reference](/commands/).

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

## The Substrate

Steward drives three tools it did not write, and installs them when you `prepare host`:

- **[Podman](https://podman.io)** — rootless containers, as ordinary systemd units
- **[Caddy](https://caddyserver.com)** — hostname routing, automatic HTTPS
- **[restic](https://restic.net)** — encrypted, deduplicated backups

A `balancer` gets Caddy alone: it terminates and forwards, so a container runtime it would
never use would only be surface to patch.

Everything Steward writes is the underlying tool's own plain config file, readable by an
admin who has never heard of Steward — and left in place if Steward is removed.
