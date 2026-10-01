# Vilice

> A coordination platform for operators running managed services on infrastructure
> they control.

## Overview

Two programs, one substrate borrowed from mature tools (OpenSSH, Caddy, Podman,
systemd):

- **Vilice** — a Go CLI on every machine. It hardens the box, installs the
  dependencies, deploys apps, and keeps an honest, append-only record. You reach it
  over **scoped SSH** (a key pinned to a forced command).
- **Vilice Console** — a Rails app, the human interface. It reaches Vilice over that same
  scoped SSH, so **it can run anywhere** — a container on the box, your laptop, or a
  central server. One machine or a hundred is the same code: a fleet is the list of
  machines it holds keys for, not a mode it switches into. A box never knows it is in one.

The console is not privileged. It holds a scoped key and comes through the same door as
a person at a shell, a CI job, or an AI agent — nothing orchestrates from beside it.

Built on the [Agora Constitution](blueprint/agora.md): every actor named, every action
accountable, the privileged ceiling small and legible — as mechanism, not commentary.

## This repository is a proof of concept

**Most of the code here was written by an LLM** (Claude), from a specification that is
itself the canonical artifact — `blueprint/` is 6,900 lines of prose that came first, and
the code is a projection of it. That is worth saying plainly rather than leaving a reader
to infer it from the commit trailers.

It has a consequence. [Codeberg's Terms of Use](https://codeberg.org/Codeberg/org/src/branch/main/TermsOfUse.md)
§ 2 (1) 7 prohibits projects that *mostly consist of code written by "generative AI"
tools*, and this one does. So this repository lives on GitHub, where that clause does not
apply, and it is a **proof of concept** — the thing that proved the design works.

**The intention is to rewrite the Vilice core by hand and host it on Codeberg**, from
this same blueprint, with an LLM as **editor and critic only** — reviewing code a human
wrote, never writing it. Not to launder provenance, which retyping would not change, but
because human authorship is what makes the work *ownable*, and an MIT or AGPL licence over
code nobody can own is a weak instrument. The full reasoning, including what that rewrite
risks, is in [`decisions/the-core-is-handwritten.md`](decisions/the-core-is-handwritten.md).

The Console is not part of that plan for now, and its provenance is unchanged.

**Start at [`blueprint/overview.md`](blueprint/overview.md).** The repo:

```
blueprint/    current canonical spec (start here) + the Agora constitution
decisions/    settled "why" (roads not taken); decisions/open/ = still deciding
vilice/      the Go CLI
console/      the Rails app
site/         the docs/marketing site
script/       dev helpers — script/devbox.sh sets up a dev box
install.sh    download + verify (ed25519) + install vilice on a box
```

## Commands

**Vilice** (`cd vilice`):

```bash
make build                 # build for your machine → bin/vilice
make test                  # run tests
make fmt vet               # format / vet
make build-linux           # cross-build for a linux/amd64 box → bin/vilice-linux-amd64
make keygen                # generate the ed25519 release keypair (once; private → ~/.keys)
make sign                  # build + tar + sign the release (self-verifies). VERSION from ./VERSION
make release               # sign + publish artifacts to RELEASE_DEST
```

**Install vilice on a box** (run on the box; verifies the signature first):

```bash
./install.sh 0.3.1
```

**Docs site** (`cd site`):

```bash
npm install
npm run serve              # local preview
npm run build              # → dist/
```

**Vilice Console** (`cd console`):

```bash
bin/rails server           # → http://localhost:3000
```

The top-level `Makefile` delegates the common ones: `make build | test | sign |
release | site-build`.

## Develop against a real box

To build Vilice Console against a real Vilice, point `script/devbox.sh` at any Linux box you
can SSH into — a spare machine, a homelab VM, or a cheap VPS. **A Hetzner box and your
local box are the same flow, just a different IP.** It builds Vilice, copies it over, runs
`prepare`, authorizes a fresh dev key, and proves the scoped-SSH path end to end:

```bash
# name the box by an ssh-config Host alias (recommended) …
script/devbox.sh up --ssh devbox
# … or inline:  DEVBOX_HOST=1.2.3.4 DEVBOX_ADMIN_KEY=~/.ssh/key script/devbox.sh up

script/devbox.sh ssh status --ssh devbox    # drive it as Vilice Console will (scoped key)
script/devbox.sh push --ssh devbox          # rebuild + reinstall as you iterate
script/devbox.sh deauth --ssh devbox        # revoke the dev key (box stays intact)
```

`up` ends by printing a `Machine.create!(…)` snippet to register the box in Vilice Console
(`bin/rails runner`). Then Vilice Console, running locally, drives a real box — exactly as in
production.

The box must be **Ubuntu 26.04 (or 24.04+)**, amd64 or arm64, with a **sudo-capable** admin login
(`DEVBOX_ADMIN`, default `root`) — older releases ship a Podman too old for Quadlet, which
`doctor` will flag. Everything else is env-configured; run `script/devbox.sh` with no args
to see the options. On a cloud box, mind the **provider firewall** — a Hetzner Cloud
Firewall can block inbound `22` even when the box itself is fine.

## Contributing

[`CONTRIBUTING.md`](CONTRIBUTING.md). Contributions are **inbound = outbound** — your change
ships under the licence of the file it touched, you keep your copyright, and there is no CLA
to sign. Two things it asks for that most projects don't: start at the blueprint, and say if
a machine wrote the code.

## License

Copyright (c) 2026 Nick Demarest. A permissive substrate under a copyleft application
(the reasoning is in [`decisions/licensing.md`](decisions/licensing.md)):

- **Vilice** (the substrate) → **MIT** — [`vilice/LICENSE`](vilice/LICENSE). `install.sh`
  installs the substrate and is MIT with it.
- **Everything else, including Vilice Console** (the control plane) → **AGPL-3.0-or-later**
  — [`LICENSE`](LICENSE) at the root.
- The **Agora constitution** text ([`blueprint/agora.md`](blueprint/agora.md)) → **CC BY-SA
  4.0**, stated in the document itself.
- The **examples** ([`examples/`](examples/)) → **MIT**, because they are meant to be copied
  into your own projects.

Open core, private edges: the platform is open; client-specific config and secrets
never live in core.
