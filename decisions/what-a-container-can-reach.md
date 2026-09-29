# What a container can reach

> Decided 2026-09-29, by measuring rather than reasoning. An app container cannot reach
> another app's published port; it can reach the cloud metadata service. Raised while
> moving Caddy's admin API to a socket
> ([`caddy-admin-socket.md`](caddy-admin-socket.md)), which closed the worst thing that
> sat on the host's loopback but did not answer the general question.

## The question

Every claim about app isolation on a shared box rests on the network: accessories are
"reachable on that network and nowhere else", and an app's port is published to
`127.0.0.1` so only Caddy reaches it. Both are claims about what a *container* can open,
and neither had been tested. Podman's rootless networking defaults (pasta) have changed
between versions, and nothing in Steward pins them, so the honest position was "unknown".

An unknown here is not academic. If a container can open the host's loopback, then one
app reaches another app's port directly — past Caddy, past the accessory network — and
`decisions/accessories-belong-to-one-app.md` is describing something the box does not do.

## What was measured

On a live Hetzner box, 2026-09-29: Ubuntu 26.04.1 LTS, rootless Podman 5.7.0, pasta
networking, container run as the `steward` user.

| Target | Result |
|---|---|
| Another app's port on the host's `127.0.0.1` | **Refused.** Both via `host.containers.internal` and via the address it resolves to (`169.254.1.2`), while `curl` on the host served the same port normally. |
| `169.254.169.254` — cloud metadata | **Answered.** Instance id, hostname, region, MAC, full network config. |
| `169.254.169.254/latest/user-data` | 404 on this box, because it was created without user-data. It is the same endpoint, so a box created *with* user-data serves it to any container. |
| Outbound generally | Unrestricted; `harden` allows all egress. |

## What it means

**The isolation claims hold.** Publishing to `127.0.0.1` is a real boundary, not a
convention — which is what the accessory model and the Caddy-in-front model both assume.
Recorded in [`../blueprint/steward/deploy.md`](../blueprint/steward/deploy.md) so the
property is stated where the spec makes the claim, with the versions it was verified
against, because a default that changed once can change again.

**Metadata is a live exposure, and a small one here.** Hetzner's metadata has no
credentials in it. The disclosure is the box's own identity and network shape — much of
which a container can already infer — plus `user-data`, which is the part that matters.
So the mechanism-free rule is the one that gets written down: **never put a secret in
cloud-init user-data on a box that runs apps.** App secrets already have a path that
never touches metadata (the deploy envelope into Podman's secret store).

## Roads not taken

- **Pin the network options in the unit renderer** (an explicit pasta/network directive on
  every app unit) so the defaults cannot drift under us. Tempting, and rejected for now:
  it would hard-code a Podman-specific flag into every unit to defend against a change
  that has not happened, and the renderer's directive allowlist is deliberately small. The
  measured property plus the versions it was measured on is the cheaper guard; re-measure
  on a Podman major bump.
- **Reject `169.254.169.254` box-wide in `harden`.** Simple, and the failure mode is
  worse than the problem: cloud-init reads metadata on boot to configure the network, so a
  blanket rule risks a box that comes back up unreachable. `harden` is also deliberately
  generic and knows nothing about containers.
- **Reject it for the `steward` user only** (an `--uid-owner` match, since pasta runs as
  that user). This is the version that would work, and it stays in
  [`open/steward-open-questions.md`](open/steward-open-questions.md) rather than being
  built: a firewall rule per box, for information disclosure with no credentials in it, is
  mechanism ahead of need. It becomes worth building the day Steward runs on a substrate
  whose metadata service hands out credentials.
