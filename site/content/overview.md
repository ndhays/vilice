---
nav: overview
title: Overview
---
# Overview

**Contents:** [Roles](#roles) &middot; [Apps](#apps) &middot; [AppConfig](#appconfig) &middot; [Spec](#spec)

Steward hosts web applications on a Linux server. It is one Go binary — a gate and a
scribe, not a runtime. Every action is a named actor, a declared scope, and a record
written before it runs, and there is no path to the box's power that skips that.

## Roles

A box says what it is for when you prepare it, and what gets installed follows from that.
There are two roles, because there are two things a box does here.

<div class="roles">
<div class="role">
<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3.5" width="18" height="7" rx="1.5"/><rect x="3" y="13.5" width="18" height="7" rx="1.5"/><line x1="6.5" y1="7" x2="6.5" y2="7"/><line x1="6.5" y1="17" x2="6.5" y2="17"/></svg>
<h3>host</h3>
<p>Runs your apps, as rootless containers under systemd. Gets Podman, Caddy and restic.</p>
<p class="role-cmd"><code>sudo steward prepare host</code></p>
</div>
<div class="role">
<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="5" cy="12" r="2.5"/><circle cx="19" cy="5.5" r="2.5"/><circle cx="19" cy="18.5" r="2.5"/><path d="M7.4 11 16.6 6.5"/><path d="M7.4 13 16.6 17.5"/></svg>
<h3>balancer</h3>
<p>Fronts other boxes and runs no apps of its own. Gets Caddy alone — a container runtime
it would never use is only surface to patch.</p>
<p class="role-cmd"><code>sudo steward prepare balancer</code></p>
</div>
</div>

A balancer owns `:80` and `:443` and therefore cannot sit behind itself; that is what makes
it a role rather than an app. Anything that *can* run in a container is an app, which is
why the list is short and stays short. Re-preparing a box as a different role is refused —
converting a machine is a decision, not a typo.

## Apps

An app on Steward is a container image, a hostname, and a document that says how they go
together. Nothing else: no cluster, no scheduler, no controller loop.

[`steward deploy`](/commands/deploy.html) pulls the image, brings the new container up
alongside the one already serving, polls it until it answers healthy, and only then moves
traffic across. If it never answers, the old app is left running and the deploy fails — a
bad image costs you an error message, not an outage. The image that was serving is
remembered as last-good, so [`steward rollback`](/commands/rollback.html) is always
available.

Images are **digest-pinned** (`ref@sha256:…`). A tag is refused, because a tag is not a
thing you can redeploy: it means something different tomorrow, and *"the image that was
running"* has to be an answer.

Steward drives three tools it did not write — [Podman](https://podman.io) for rootless
containers, [Caddy](https://caddyserver.com) for routing and automatic HTTPS, and
[restic](https://restic.net) for encrypted backups. Everything it writes is the underlying
tool's own plain config file, readable by an admin who has never heard of Steward, and left
in place if Steward is removed.

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
