# A trust core and verb packs

> Decided 2026-08-02. Steward splits into a small **core** — the gate, the record, the
> ceiling — and **verb packs** it dispatches to. One binary for now, internally layered.
> Discovery is one fixed root-owned directory; a root-owned manifest, not the directory,
> is what authorizes.
>
> Builds on [`orchestrators-are-clients.md`](orchestrators-are-clients.md) (everything
> above the core is a client) and applies [`borrowed-substrate.md`](borrowed-substrate.md)
> to our own extensions.

## The question

The binary is ~4,600 lines of production code doing two jobs. One is being a trust core:
the forced-command dispatcher, three scopes, the pre-act chain, `verify`, and the root
ceiling. The other is deploying apps: pull the image, write the Quadlet unit,
health-check, flip Caddy. Those change at different speeds and are trusted for different
reasons, and folding them together means the security surface a skeptical reader must
audit is the whole binary — including every feature we add next.

They also cannot simply be separated by moving deploy into a remote CLI: the deploy
logic has to *execute on the box*, and a remote CLI that could execute arbitrary steps
there is the shell problem again ([`no-key-gets-a-shell.md`](no-key-gets-a-shell.md)).

## The decision

**Two layers, one binary.** The core owns the gate, the record, the ceiling, identity,
and pack dispatch. Packs own the verbs. Packs are named by domain, not substrate
([`the-names-are-steward.md`](the-names-are-steward.md)).

**Core forever, never a pack:** `prepare`, `harden`, `uninstall`, `authorize`, `revoke`,
`verify`, `record`, `snapshot`, `_exec`. The commands that *constitute* the trust model
cannot be plugins, or the trust model has a plugin interface — and the whole design is
that it does not.

The point is that the core can be **finished**: audited, versioned slowly, small enough
for one person to hold in their head, while verbs churn at product speed. Its stability
becomes a security property rather than a lack of progress.

## Discovery: one fixed directory, never `$PATH`

Packs are found in a single root-owned directory (`/usr/libexec/steward/`, the
FHS-correct home for internal executables), root-owned, `0755`, with no user-writable
ancestor. **Not configurable** — no flag, no `STEWARD_PACK_PATH`, no config key.

Git discovers `git-foo` on `$PATH` and this is the convention every operator has in
their fingers, so it is worth saying exactly why we reject it. For git, plugin discovery
is a convenience feature. Here it is attack surface. `$PATH` is per-user,
per-environment, and writable by anything that can touch a shell profile or the
invocation's environment. If the core resolved `steward-backup` through it, anyone who
could place a binary earlier in the search order would have injected code that runs with
Steward's privileges **and is recorded in the chain under an innocent verb name**. The
chain would faithfully log `backup` while executing something else — worse than no
chain, because it launders the lie. Un-bypassability would quietly acquire the footnote
"assuming a trustworthy `$PATH`," and ambient trust of that kind is what the design
exists to refuse.

Configurability is the same hole with documentation. Any knob that redirects discovery
reintroduces the problem through a side door, so there is no knob: an admin who genuinely
wants a different location recompiles or bind-mounts. The friction is the feature.
Enforcement is filesystem ownership, which is invariant 3 and the same mechanism as the
ceiling ([`ceiling-is-the-machine.md`](ceiling-is-the-machine.md)).

## The directory locates; the manifest authorizes

Presence on the shelf is not permission. The core execs only what
`/etc/steward/packs.manifest` — root-owned, at its own fixed path — lists by **name and
SHA-256**. A binary in the right directory with the wrong hash is refused identically to
one that is not there. This is the `@sha256` image rule ([`quadlet-deploy.md`](quadlet-deploy.md))
turned on ourselves: we already refuse to run a container image we cannot name by digest,
and there is no principled reason to hold our own extensions to a weaker standard.

Because the manifest is the boundary, the directory can be sloppily managed without the
trust model caring.

**Close the race.** The naive sequence — hash the file, then exec the path — leaves a
TOCTOU gap where the file is swapped between check and exec. The core must open the
file once, hash *that descriptor*, and exec *the same descriptor* (`execveat` with
`AT_EMPTY_PATH`). This is the difference between "we pin digests" as a claim and as a
property. `execveat` is reachable from the standard library; adding `golang.org/x/sys`
for it would cost the zero-dependency property, which is not a trade worth making for
one syscall.

The hashing half is built and already reads a descriptor rather than a path. The exec
half arrives with the first pack that is a separate file — until then there is nothing
to exec, and unexercised syscall code is a liability rather than a head start.

**Authorizing a pack is itself a recorded act.** The manifest changes only through the
core, at `grant` scope, writing the new entry *and* appending a chain record: actor,
pack, digest, time. So "what code was ever authorized to run on this box, added by whom,
when" is answerable from the chain alone — a question no plugin system usually lets you
ask, falling out of machinery that already exists.

## One founding pack, not three

An earlier sketch had three internal packs from the start — `app`, `backup`, `diag` —
on the reasoning that they already live in separate files and that N>1 would exercise
discovery properly. Measuring the actual symbol coupling killed that:

- `backup.go` reaches into **13** app internals (`runDeploy`, `loadApp`, `podman`,
  `podmanOutput`, `userExec`, `validateState`, `appPath`, `appState`, …).
- `doctor.go` and `status.go` reach into **10** (`listApps`, `loadApp`, `podman`,
  `containerName`, `loggedInRegistries`, `registryCoverageCheck`, …).

File separation is real; symbol separation is not. Splitting them now means exporting a
wide app-internals API purely so the pieces can call each other across a line that buys
nothing — the opposite of a boundary. So **v1 has one pack, `steward-app`**, holding
deploy, quadlet, registry, backup, logs, doctor, and status. `steward-backup` and
`steward-diag` split out when they are real packs with their own substrate, which is
what the catalog always said they were: later ones.

This is the same rule as the physical split, applied one level down — a real second use
case triggers it, not symmetry.

## Three seams, not two

Drawing the line exposes exactly where the core currently knows too much. Measured, not
guessed:

1. **`prepare`** — `provision.go` calls `podman`. The ceiling installs a pack's
   substrate.
2. **`status` / `doctor`** — the core's `harden.go` reaches into `hardeningPath`, while
   `doctor`/`status` reach into app internals. The hardening posture is core state
   filed in a pack; the container and route reporting is pack state surfaced by a core
   verb.
3. **`uninstall`** — the one the sketch missed. `uninstall.go` needs `listApps` and
   `appState` to plan and confirm, and `loadBackupConfig` / `resticPasswordFile` /
   `secretsDir` to print the backup warning that is the operator's last chance to save a
   restic password. So the contract needs a **teardown** side, not just a prepare side:
   a pack must be able to declare what it has on the box, and what the operator must
   know before it goes.

Note what `uninstall` does *not* need: it already removes apps by invoking Steward's own
`remove` verb as a subprocess rather than by reaching into deploy internals. The command
surface was already the boundary there, which is a small piece of evidence that the line
is in a plausible place.

## v1: compiled in, but the check is real

Packs ship compiled into the one binary. Their digest is the binary's own, and `prepare`
writes the manifest and records the authorization. The discovery path exists and has
exactly one shelf to look at, but **the manifest check sits on the hot path and is not
stubbed** — a mechanism that is only switched on later is a mechanism nobody has tested.

Physical separation waits for a real second pack, not for symmetry. Building plugin
machinery before a second plugin is how a small project spends a year on scaffolding.

## What it costs

- **`prepare` has to split.** Today it lays the accountability floor *and* installs
  Podman and Caddy — a pack dependency installed by the ceiling. The core half creates
  the account, state dir, record, sshd plumbing, and manifest; each pack contributes its
  own substrate step. This is the sharpest test of whether the line is real: if the core
  still mentions Podman, the line is decorative.
- **`status` and `doctor` split** the same way — the core reports the record, the chain,
  the actors, and binary drift; the pack contributes container and route sections.
- **One more indirection** in a codebase whose virtue is being readable in an afternoon.

## Roads not taken

- **Start a new repo with this one as reference.** The costly, finished part is the core;
  a rewrite re-derives exactly the code least worth re-deriving, and un-bypassability
  lives in the *absence* of paths, which does not port. The installer's chain of custody
  is also repo-shaped — `install.sh` fetches the release key from the source repo on
  purpose — so a new repo means a new key URL for no gain.
- **`$PATH` discovery, git-style.** Above.
- **Directory-only, no manifest** ("root owns the directory, that is enough"). It would
  mostly hold, and it makes the trust boundary a filesystem permission that a careless
  `install` or a package manager can widen without anyone noticing. The digest is
  checkable after the fact; a directory mode is not.
- **Ship `steward pack add` now.** With packs compiled in it cannot act, and verbs are
  forever — minting one into an append-only namespace before it can do anything is a
  name we would be stuck with. It arrives with the physical split.
- **Keep one fused binary and simply document the layers.** Documentation is not a
  boundary; the reason to draw the line in code is so that the answer to "what must I
  trust?" is checkable rather than asserted.
