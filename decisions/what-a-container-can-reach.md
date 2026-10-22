# What a container can reach

> Decided 2026-09-29, by measuring. Raised by
> [`caddy-admin-socket.md`](caddy-admin-socket.md). The property is stated in
> [`../blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md).

## The question

App isolation on a shared box rests on two claims: an accessory is reachable only on its
own network, and an app's port is published to `127.0.0.1` so only Caddy reaches it.
Neither had been tested. Podman's rootless networking defaults have changed between
versions and Vilice pins none of them.

## What was measured

A live Hetzner box: Ubuntu 26.04.1 LTS, rootless Podman 5.7.0, pasta networking,
container run as `_vilice`.

| Target | Result |
|---|---|
| Another app's port on the host's `127.0.0.1` | **Refused**, both via `host.containers.internal` and the address it resolves to (`169.254.1.2`). |
| `169.254.169.254` — cloud metadata | **Answered.** Instance id, hostname, region, MAC, network config. |
| `169.254.169.254/latest/user-data` | 404 here, because the box had none. A box created with user-data serves it to any container. |
| Outbound generally | Unrestricted; `harden` allows all egress. |

## What it means

- **The isolation claims hold.** Publishing to `127.0.0.1` is a real boundary.
- **Metadata is a small, live exposure.** Hetzner's has no credentials. The part that
  matters is `user-data`. **Never put a secret in cloud-init user-data on a box that runs
  apps.** App secrets already travel by the deploy envelope.

**Re-measure on a Podman major bump.**

## Roads not taken

- **Pin the network options in the unit renderer.** Hard-codes a Podman-specific flag
  into every unit against a change that has not happened, and the renderer's directive
  allowlist is deliberately small.
- **Reject `169.254.169.254` box-wide in `harden`.** cloud-init reads metadata on boot to
  configure the network; a blanket rule risks a box that comes back unreachable.
- **Reject it for the `_vilice` user only** (`--uid-owner`). This one would work. Not
  built: a firewall rule per box for disclosure with no credentials in it. Worth building
  the day Vilice runs where metadata hands out credentials. Tracked in
  [`open/vilice-open-questions.md`](open/vilice-open-questions.md).
