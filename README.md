# Steward

> A coordination platform for operators running managed services on infrastructure
> they control.

## Overview

Two programs, one substrate borrowed from mature tools (OpenSSH, Caddy, Podman,
systemd):

- **Steward** — a Go CLI on every machine. It hardens the box, installs the
  dependencies, deploys apps, and keeps an honest, append-only record. You reach it
  over **scoped SSH** (a key pinned to a forced command).
- **Steward Console** — a Rails app, the human interface. It reaches Steward over that same
  scoped SSH, so **it can run anywhere** — a container on the box, your laptop, or a
  central server. One machine or a hundred is the same code: a fleet is the list of
  machines it holds keys for, not a mode it switches into. A box never knows it is in one.

The console is not privileged. It holds a scoped key and comes through the same door as
a person at a shell, a CI job, or an AI agent — nothing orchestrates from beside it.

Built on the [Agora Constitution](blueprint/agora.md): every actor named, every action
accountable, the privileged ceiling small and legible — as mechanism, not commentary.

**Start at [`blueprint/overview.md`](blueprint/overview.md).** The repo:

```
blueprint/    current canonical spec (start here) + the Agora constitution
decisions/    settled "why" (roads not taken); decisions/open/ = still deciding
steward/      the Go CLI
console/      the Rails app
site/         the docs/marketing site
script/       dev helpers — script/devbox.sh sets up a dev box
install.sh    download + verify (ed25519) + install steward on a box
```

## Commands

**Steward** (`cd steward`):

```bash
make build                 # build for your machine → bin/steward
make test                  # run tests
make fmt vet               # format / vet
make build-linux           # cross-build for a linux/amd64 box → bin/steward-linux-amd64
make keygen                # generate the ed25519 release keypair (once; private → ~/.keys)
make sign                  # build + tar + sign the release (self-verifies). VERSION from ./VERSION
make release               # sign + publish artifacts to RELEASE_DEST
```

**Install steward on a box** (run on the box; verifies the signature first):

```bash
./install.sh 0.2.0beta
```

**Docs site** (`cd site`):

```bash
npm install
npm run serve              # local preview
npm run build              # → dist/
```

**Steward Console** (`cd console`):

```bash
bin/rails server           # → http://localhost:3000
```

The top-level `Makefile` delegates the common ones: `make build | test | sign |
release | site-build`.

## Develop against a real box

To build Steward Console against a real Steward, point `script/devbox.sh` at any Linux box you
can SSH into — a spare machine, a homelab VM, or a cheap VPS. **A Hetzner box and your
local box are the same flow, just a different IP.** It builds Steward, copies it over, runs
`prepare`, authorizes a fresh dev key, and proves the scoped-SSH path end to end:

```bash
# name the box by an ssh-config Host alias (recommended) …
script/devbox.sh up --ssh devbox
# … or inline:  DEVBOX_HOST=1.2.3.4 DEVBOX_ADMIN_KEY=~/.ssh/key script/devbox.sh up

script/devbox.sh ssh status --ssh devbox    # drive it as Steward Console will (scoped key)
script/devbox.sh push --ssh devbox          # rebuild + reinstall as you iterate
script/devbox.sh deauth --ssh devbox        # revoke the dev key (box stays intact)
```

`up` ends by printing a `Machine.create!(…)` snippet to register the box in Steward Console
(`bin/rails runner`). Then Steward Console, running locally, drives a real box — exactly as in
production.

The box must be **Ubuntu 26.04 (or 24.04+) / amd64** with a **sudo-capable** admin login
(`DEVBOX_ADMIN`, default `root`) — older releases ship a Podman too old for Quadlet, which
`doctor` will flag. Everything else is env-configured; run `script/devbox.sh` with no args
to see the options. On a cloud box, mind the **provider firewall** — a Hetzner Cloud
Firewall can block inbound `22` even when the box itself is fine.

## License

A permissive substrate under a copyleft application (see
[`decisions/licensing.md`](decisions/licensing.md)):

- **Steward Console** (the control plane) → **AGPL-3.0**.
- **Steward** (the substrate) → **MIT**.
- The **Agora constitution** text → CC BY-SA 4.0.

Open core, private edges: the platform is open; client-specific config and secrets
never live in core. *(Binding LICENSE files added once confirmed.)*
