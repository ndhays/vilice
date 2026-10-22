# Licensing

> Decided 2026-06-03; binding 2026-08-11, when the LICENSE files went in. Copyright
> holder: Nick Demarest. Contributions: [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## The decision

A permissive substrate under a copyleft application.

- **Vilice Console → AGPL-3.0-or-later.** It is the part someone could host as a service;
  the network clause makes hosted forks share changes back.
- **Vilice (the CLI) → MIT.** It is small and not the moat. Permissive maximizes adoption
  and trust, and AGPL's network clause does not fit a CLI. (Apache-2.0 if a patent grant
  is ever wanted.)
- **Agora constitution text → CC BY-SA 4.0.** A document, not code.

**"or-later", not "only".** `-only` creates friction combining with future-GPL code, and
`-or-later` is the FSF's recommendation. The cost: it binds the project to terms not yet
written.

## Why license before the core is handwritten

[`the-core-is-handwritten.md`](the-core-is-handwritten.md) argues machine-generated code
is not protectable, so a copyleft over it is weak. That is a reason for the rewrite, not
for shipping unlicensed:

- **No LICENSE means "all rights reserved."** A repo that says the substrate is MIT while
  granting nothing is a broken promise.
- **A licence grants what you own.** The human-authored parts, the selection and
  arrangement, and the blueprint are ownable. Whatever is not was already free to take.
- **The rewrite strengthens the same file.** Same holder, same terms; no relicensing.

## Open core, private edges

The console is both the open project and the software the maintainer runs for clients.
Client-specific config, secrets and private integrations are never in core.

## Roads not taken

- **A CLA or copyright assignment**, to allow relicensing later. The power a CLA collects
  is the power that makes capture possible. Contributions are inbound = outbound;
  relicensing would need every contributor's agreement, which is the point. Contributors
  are asked to declare provenance, because human authorship is a licensing question here.
- **An all-AGPL monorepo.** MIT serves an adoptable, auditable substrate better, and the
  capture worth preventing — a proprietary hosted console — is covered by AGPL on the
  console. Accepted: someone could build a closed control plane on Vilice.

## Mechanics

- Root `LICENSE` = AGPL-3.0 verbatim, unmodified. The copyright line lives in `README.md`
  and per-file notices, so licence detection stays clean.
- `vilice/LICENSE` = MIT.
- `examples/LICENSE` = MIT — examples exist to be copied.
- `install.sh` = MIT by SPDX header; it sits at the root but installs the substrate.
- `blueprint/agora.md` = CC BY-SA 4.0, noted in the file.
- No blanket SPDX sweep; headers go only where the nearest LICENSE file is not the answer.
- `script/`, `audit/`, and the prose in `blueprint/` and `decisions/` stay under the root
  AGPL. A fourth licence costs more to explain than the oddity.
