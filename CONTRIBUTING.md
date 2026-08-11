# Contributing

Read [`README.md`](README.md) first, especially the part that says this repository is a
**proof of concept** whose code was mostly written by an LLM. That is unusual enough to
change what contributing here means, so it comes before the mechanics.

## Licensing — inbound = outbound

**Your contribution ships under the licence of the file you changed.** Nothing to sign: no
CLA, no copyright assignment. You keep your copyright; the project gets a licence on the
same terms it gives everyone else.

| What you changed | Licence |
| --- | --- |
| `steward/`, `install.sh`, `examples/` | MIT |
| Everything else, including `console/` | AGPL-3.0-or-later |
| `blueprint/agora.md` (the constitution text) | CC BY-SA 4.0 |

Opening a pull request is your statement that you wrote the change, or otherwise have the
right to submit it, and that you licence it under the terms above. If you *can't* make that
statement — the code is your employer's, or it came from a project under different terms —
say so in the pull request rather than leaving it implied. The reasoning behind the split is
in [`decisions/licensing.md`](decisions/licensing.md).

## Provenance — say if a machine wrote it

Here this is a licensing fact, not a style preference. The project's copyright position
([`decisions/the-core-is-handwritten.md`](decisions/the-core-is-handwritten.md)) turns on
human authorship: purely machine-generated code isn't protectable, and **you cannot license
what you do not own.**

- **In this repository, say so and it's fine.** If an LLM wrote or substantially drafted the
  change, note it in the pull request. It is not disqualifying — most of this code was
  written that way and the README says so plainly.
- **The handwritten core is different.** The intention is to rewrite Steward's core by hand
  from the same blueprint, because "a human wrote and understands every line of the gate" is
  the claim worth being able to make. Machine-drafted code cannot land there. An LLM as
  reviewer or critic of code a human wrote is fine, and encouraged.

## Start at the blueprint

`blueprint/` is canonical truth; the code is a projection of it. So:

- **Read [`blueprint/overview.md`](blueprint/overview.md) before changing behavior.**
- **A behavior change updates the blueprint in the same commit.** Drift turns the spec into
  fiction, which is worse than no spec.
- Settled reasoning — especially a road not taken — goes in `decisions/`. Questions still
  being decided live in `decisions/open/`; if your change answers one, move it out, and if it
  raises one, add it.

## Before you open a pull request

```bash
cd steward && make fmt vet test    # Go: format, vet, test
cd steward && make audit           # govulncheck + gosec (needs network)
cd steward && make fuzz            # if you touched a parsing or rendering boundary
cd console && bin/ci               # Rails: rubocop, brakeman, gem audit, tests, seeds
cd site    && npm run build        # docs site still builds
```

`bin/ci` is the whole Console check; `bin/rails test` alone if you just want the tests.

From the repo root, `make test` and `make audit` cover the Go side.

Keep changes **small, one concern at a time, and revertible** — the same discipline the
system enforces on the machines it manages. Commit messages here are plain sentences saying
what changed, not `feat:`-style prefixes; skim `git log` and match it.

## Security

**Don't open a public issue for a vulnerability.** Email `security@agoraforge.org` — see
[`SECURITY.md`](SECURITY.md) for what to include and how disclosure is handled.

## What review is strict about

One claim holds the whole design up: **there is no path to a machine's power that skips a
scoped, recorded invocation.** A change that adds a path around the gate will not land, no
matter how good it is otherwise. Concretely, every change keeps:

1. **Every caller a named actor with a declared scope** — scoped SSH, a key pinned to a
   forced command, `authorized_keys` as the inspectable ledger.
2. **The record written before the action runs** — append-only and hash-chained. Nothing
   privileged happens off the books.
3. **The privileged ceiling small and legible** — only `prepare` and `harden` run as root,
   enforced by filesystem ownership rather than convention.

If you can't name the mechanism that enforces the invariant your change touches, the change
isn't finished yet.
