# Roles, not packs — a box says what it is for

> Decided 2026-08-06. Spec:
> [`../blueprint/vilice/provision.md`](../blueprint/vilice/provision.md). Replaces the
> pack design, which split the binary into a trust core and verb packs dispatched through
> a root-owned manifest.

## The decision

- **Vilice hosts web applications on a Linux server.** Not general administration; Cockpit
  does that ([`open/landscape-scan.md`](open/landscape-scan.md)).
- **Packs are dropped.** One binary, all verbs, no plugin layer.
- **A box declares a role** — `vilice prepare host` or `vilice prepare balancer` — and
  what is installed and which ports open follow from it.

## Why packs go

Neither argument alone would be enough.

- **The seam has nothing on the far side.** The hypothetical second and third packs were
  backup and diagnostics. Once the product is "host web apps", those are the product. No
  second pack ever appeared.
- **The handwritten rewrite does the same job.** The split existed to bound what a
  skeptical reader must trust. Handwriting
  ([`the-core-is-handwritten.md`](the-core-is-handwritten.md)) bounds it by making the
  whole binary understood by the person who wrote it. Two mechanisms for one goal is one
  too many.

## What is kept

- **The binary digest check.** `prepare` records the sha256 of the binary; every verb
  checks the running binary against it before it runs. Swap `/usr/local/bin/vilice` and
  the verb refuses, and the refusal is recorded. `verify`, `record`, `actors`,
  `authorize` and `revoke` skip the check, so an operator can inspect and repair a box
  whose binary was replaced.
- **The internal seam.** `internal/core/` and the verb implementations stay separate,
  with a documented line. The core knows about apps in three places: `prepare` (installs
  the app layer's substrate), `status`/`doctor`, and `uninstall` (which removes apps by
  running `remove` as a subprocess).

**Gone:** the discovery directory `/usr/libexec/vilice/` (always empty), the
`$PATH`-as-attack-surface reasoning, and the `execveat` TOCTOU closure, which was only
ever prose.

## Roles are a closed set

> **If it can run in a container, it is an app, not a role.**

A role owns the machine's network position, needs privileged setup, or needs substrate no
app host needs. A registry, a database, a monitoring stack, the Console — all apps.

| Role | Why it is one |
|---|---|
| `host` | runs containers: Podman, uidmap, restic, Caddy |
| `balancer` | owns :80/:443 and so cannot sit behind itself; Caddy alone |

`vpn` passes the test and is out of scope
([`the-vpn-is-not-a-control-path.md`](the-vpn-is-not-a-control-path.md)). `mail`, `dns`
and `storage` pass it and are different products. A third role waits for a third real
case; a role is a word in a file and a switch statement.

## What the role buys

- **Substrate follows purpose.** A balancer does not install Podman and restic.
- **`deploy` refuses by name** on a balancer.
- **The machine view shapes itself around the role.**
- **It is recorded** — `prepare-role` in the chain.

## Ports move to the role

Whether a box serves web is a fact about its role, not its lockdown. `harden` opens
sshd's port and nothing else; `prepare <role>` opens what the role serves.

- **The port allowed is the one sshd is configured for**, never the constant 22. A remote
  lockout has no repair.
- **`prepare` never installs or enables a firewall.** `harden` is optional and `prepare`
  is required; a dependency would make hardening mandatory and break "a box is
  accountable even un-hardened".

## `status` always includes security

The section used to be omitted when no posture had been published, so a never-hardened
box looked like a box with nothing to report. Absence is a fact here.

## What it costs

- "What must I trust?" becomes the binary, not the core. Acceptable only because of the
  rewrite.
- A third role is a code change.
- The console loses `PackState` and the pack-shaped machine view.

## Roads not taken

- **Keep packs, ship separate binaries.** A balancer needing only Caddy argues for
  conditional substrate, not two binaries. Separate binaries buy independent release
  cadence and per-pack digest pinning, which a solo project with one pipeline does not
  need.
- **Packs as per-app features** (`pack-backup`). That is a dependency, and the AppConfig
  already states it.
- **Merge `harden` into `prepare`.** Forces either mandatory hardening (wrong for a box
  behind a cloud firewall or its own CIS baseline) or optional accountability. The useful
  part — firewall policy follows the role — was taken without the merge.
- **A `worker` role.** Same substrate as `host`, different ports: a host with a port
  profile.
- **Rename `harden`** to `lockdown` or `baseline`. `harden` is jargon. `lockdown` swaps
  one metaphor for another and implies it ends; `baseline` is not clearly better. A
  lateral rename costs record continuity, and people search for how to harden a server.
  The fix is the frame, and `harden --check`, which reads `sshd -T` and `ufw` and reports
  drift.
