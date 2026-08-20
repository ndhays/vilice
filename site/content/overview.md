---
nav: overview
title: Overview
---
# Overview

**Contents:** [Not Your Admin Access](#not-your-admin-access) &middot; [Roles](#roles) &middot; [Apps](#apps) &middot; [AppConfig](#appconfig) &middot; [Spec](#spec) &middot; [Secrets](#secrets) &middot; [Examples](#examples)

Steward hosts web applications on a Linux server. It is one Go binary — a gate and a
scribe, not a runtime. Every action is a named actor, a declared scope, and a record
written before it runs, and there is no path to the box's power that skips that.

## Not Your Admin Access

**Steward is the accountable control plane. It is not how you administer the box.**

No key gets a shell, at any scope — an empty command is refused at every rung. That is
not a missing feature, it is the mechanism. A shell as the `steward` user could run
containers directly, hand-write a unit, or rewrite Caddy's config, and none of it would
reach the record: the log would show that a session opened at 14:32 and nothing about
what it did. One unrecorded door is enough to end the claim, so there isn't one.

So Steward offers no route to a database console, a one-off script, or a look around the
filesystem. You reach those the way you always have — SSH to the box as **yourself**, with
your own account and your own key, separate from the scoped keys Steward holds.

Which means Steward **sits alongside the tools you already use** rather than replacing
them. Keep your shell, Cockpit, Ansible, your provider's web console. Steward is not
competing for that job and does not want it. What it adds is that the operations that
matter — deploy, roll back, start, stop, remove, grant a key — leave a trail naming who
did them and when.

Reading is different, and is offered: `steward status`, `steward logs`, and
`steward record` are `observe` scope, because looking changes nothing.

## Roles

Steward prepares a box for a specific role.

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

### Note on Roles

A balancer is a separate role precisely because it owns `:80` and `:443` and would not
function inside a container. Steward CLI also enforces that once a box is prepared for one
role, it cannot be re-prepared as the other — converting a machine is a decision, not a
typo. (Re-stating the role it already has is idempotent, like the rest of `prepare`.)

## Apps

An app on Steward is a container image that is defined with a JSON config.

[`steward deploy`](/commands/deploy.html) pulls the app image, brings the new container up
alongside the one already serving, polls it until it answers healthy, and only then moves
traffic across. If it never answers, the old app is left running and the deploy fails — a
bad image costs you an error message, not an outage. The image that was serving is
remembered as last-good, so [`steward rollback`](/commands/rollback.html) is always
available.

Images are **digest-pinned** (`ref@sha256:…`) so there is never confusion about which
version of the app is deployed and running.

Steward drives helpful open source hosting tools it did not write —
[Podman](https://podman.io) for rootless containers, [Caddy](https://caddyserver.com) for
routing and automatic HTTPS, and [restic](https://restic.net) for encrypted backups.
Everything it writes uses the underlying tool's config, so it is readable by an admin who
has never heard of Steward, and left in place if Steward is removed.

## AppConfig

The AppConfig defines the app. It exists separately from its app code (which means the same
codebase image could be deployed in different configurations to different machines). A
change in config is necessarily a redeployment.

Here is an example of the AppConfig (Steward Console itself):

```jsonc
// console.json — the desired state, recorded by digest on every deploy
{
  "image":     "ghcr.io/agoraforge/steward-console@sha256:…",
  "hostnames": ["console.example"],
  "port":      4000,
  "health":    "/up",
  "env":       { "HTTP_PORT": "4000" },
  "secrets":   ["RAILS_MASTER_KEY"],
  "volumes":   ["steward-console-storage:/rails/storage"],
  "release":   ["bin/rails", "db:migrate"]
}
```

[`steward deploy`](/commands/deploy.html) reads this as the `app` half of an envelope on
stdin. The other half carries the [secret values](#secrets), which the config itself never
holds.

### Spec

| Field | Type | Required | Description |
|---|---|---|---|
| `image` | string | yes | The container image, **digest-pinned** (`name@sha256:…`). Tags aren't stable; the digest is the code's identity. |
| `hostnames` | string[] | yes | The hostnames Caddy routes to this app. TLS is issued automatically. Each must be a site address — `app.example.com`, `http://app.example.com`, `*.example.com`, or `host:port`. |
| `port` | number | yes | The port the app listens on inside its container. |
| `health` | string | no | HTTP path Steward probes before sending traffic. Defaults to root `/`. |
| `env` | object | no | Non-secret environment, as key/value pairs. Recorded in the clear. |
| `secrets` | string[] | no | **Names** of secrets the box injects as env. Values are supplied at deploy and **never recorded** — see [Secrets](#secrets). |
| `volumes` | string[] | no | Volume mounts, `name:/path/in/container`. The **declaration**, not the data; volumes survive redeploys. A host path instead of a name is a bind mount, and must live under `/srv`. |
| `processes` | object[] | no | Other containers this app runs — a worker, a clock. Each is `{ "name", "command" }` and inherits the app's **image, env, secrets and volumes**; only the command differs. They deploy and roll back with the app, so a worker can never end up running different code from the web process. `command` is **argv** (`["bin/jobs"]`), never a shell string. |
| `release` | string[] | no | A command run **once from the new image, before the new container starts** — migrations are what it is for. Given as **argv** (`["bin/rails", "db:migrate"]`), never a shell string: for more than one step, put a script in the image, where the digest covers what it does. If it fails, nothing is deployed and the running app is untouched. |

## Secrets

**A secret is a name in the config and a value on stdin.** The two never travel together,
which is what keeps the config safe to record and safe to keep in version control.

### The Envelope

`app` is the AppConfig, in full. `secret_values` is a value for each name it declares:

```jsonc
{
  "app":           { "secrets": ["RAILS_MASTER_KEY"] },  // recorded, by digest
  "secret_values": { "RAILS_MASTER_KEY": "…" }           // never recorded
}
```

Steward puts each value in the box's Podman secret store and injects it into the container
as env. Nothing about it reaches the record or the command line.

### On Every Deploy

Every name in `secrets` needs a value in `secret_values`, every time — a missing one is
refused, not carried over from last time. A value whose name the config does not declare is
refused too.

The plain way is a file, and it needs nothing you do not have:

```bash
steward deploy console < envelope.json
```

To keep the value out of a second file, build the envelope in the pipe instead. `jq` does
that in one line, though it is not on a fresh Ubuntu box — `sudo apt install jq` first:

```bash
jq --arg key "$RAILS_MASTER_KEY" \
   '{ app: ., secret_values: { RAILS_MASTER_KEY: $key } }' console.json \
  | steward deploy console
```

The deploy scripts in
[`examples/`](https://git.agoraforge.org/agoraforge/steward/src/branch/main/examples) build
the same envelope with `python3`, which every Ubuntu box already has.

## Examples

Three real apps, from the smallest thing that deploys to one that needs a secret.

### nginx — A Web Server

[nginx](https://nginx.org) answers HTTP requests and serves files. This is the smallest
config that works: the image, the hostname Caddy should route, and the port the app listens
on inside its container. Everything else takes a default — Steward polls `/` for health.

```jsonc
// nginx.json
{
  "image":     "docker.io/nginxinc/nginx-unprivileged@sha256:…",
  "hostnames": ["www.example.com"],
  "port":      8080
}
```

### Prometheus — A Metrics Database

[Prometheus](https://prometheus.io) records numbers about your services over time and
answers questions about them. Two fields more than nginx: `health`, because the path it
answers readiness on is not `/`, and `volumes`, because the numbers have to outlive the
deploy. A volume is a *name*, and the same name is still there after the next one.

```jsonc
// prometheus.json
{
  "image":     "docker.io/prom/prometheus@sha256:…",
  "hostnames": ["metrics.example.com"],
  "port":      9090,
  "health":    "/-/healthy",
  "volumes":   ["prometheus-data:/prometheus"]
}
```

### code-server — VS Code in the Browser

[code-server](https://github.com/coder/code-server) runs the VS Code editor on the box and
puts it behind a URL, so a password is the door. `PASSWORD` is a name here and a value on
stdin — see [Secrets](#secrets).

```jsonc
// code-server.json
{
  "image":     "docker.io/codercom/code-server@sha256:…",
  "hostnames": ["code.example.com"],
  "port":      8080,
  "health":    "/healthz",
  "secrets":   ["PASSWORD"]
}
```

More of these, with the deploy scripts that resolve each digest on the box, live in
[`examples/`](https://git.agoraforge.org/agoraforge/steward/src/branch/main/examples) in
the repository.
