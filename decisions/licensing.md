# Licensing

**Decided 2026-06-03. Confirmed and binding 2026-08-11** — the LICENSE files are in the
tree; copyright holder is **Nick Demarest**. Outside contributions are governed by
[`CONTRIBUTING.md`](../CONTRIBUTING.md): **inbound = outbound**, no CLA and no copyright
assignment — a contribution ships under the licence of the file it changed.

A permissive substrate under a copyleft application:

- **Vilice Console (the control plane) → AGPL-3.0-or-later.** It is the SaaS-able value surface;
  AGPL's network clause makes hosted forks share their changes back — Agora's "make
  capture expensive," encoded in the license.
- **Vilice (the substrate) → MIT.** Vilice is deliberately *small and not the moat*
  — the un-bypassable gate that borrows OpenSSH/Caddy. Permissive maximizes adoption
  and trust in the substrate, and AGPL's network clause doesn't fit a CLI anyway (it
  would behave like GPL and only deter embedding). *(Apache-2.0 is the alternative if
  a patent grant is wanted.)*
- **Agora constitution text → CC BY-SA 4.0** — it's a document, not code; separate
  from the code license.

## "or-later," not "only"

`AGPL-3.0-or-later`. The practical concern is combining with other copyleft code, and
`-only` creates friction with anything future-GPL; `-or-later` is also the FSF's own
recommendation. The cost is real and accepted: it binds the project to terms the FSF has
not written yet. Judged the smaller risk of the two, because the licence's job here is to
make hosted capture expensive, not to hedge against its own vilice.

## Why license before the core is handwritten

[`the-core-is-handwritten.md`](the-core-is-handwritten.md) argues that purely
machine-generated code is not protectable, so **you cannot license what you do not own** —
and a copyleft over largely-unownable code is a weak instrument. That is a good reason to
do the rewrite. It is not a reason to ship unlicensed, and the files were added before the
rewrite deliberately:

- **No LICENSE is not neutral, it is "all rights reserved."** Default copyright grants
  nothing. A repo that tells readers the substrate is MIT while granting no permission is
  worse than a weak grant — it is a broken promise, and the README, the site footer, and
  the Console settings page had all been making that promise for months.
- **A licence grants what you own; it does not assert what you don't.** The human-authored
  parts, the selection and arrangement, and the blueprint the code projects from are
  ownable. Whatever isn't was already free to take — withholding the file protects nothing.
- **The rewrite strengthens this same file.** Same holder, same terms, better teeth. No
  relicensing, no re-permissioning contributors.

## Open core, private edges

Vilice Console is **both** the open project *and* the software the maintainer runs for
their own clients. The platform is open; the maintainer's client-specific config,
secrets, and private integrations are **never in core** — they live as private
config/plugins/env. Keeping that line clean is what makes "open and proprietary" not a
contradiction.

## Road not taken: a CLA

Contributions are **inbound = outbound** — a change ships under the licence of the file it
touched, contributors keep their copyright, nothing to sign. Considered a CLA or copyright
assignment, which would let the project relicense later without hunting down every
contributor. Rejected: the power a CLA collects is exactly the power that makes capture
possible, and asking for it contradicts the pitch. The cost is accepted — relicensing later
would need every contributor's agreement, which is the point.

Provenance is the one thing contributors are asked to declare, because
[`the-core-is-handwritten.md`](the-core-is-handwritten.md) makes human authorship a
licensing question rather than a matter of taste: machine-drafted code is welcome in this
proof of concept and cannot land in the handwritten core.

## Road not taken: an all-AGPL monorepo

Considered one license for everything. Rejected: Vilice's value is in being a widely
adoptable, auditable substrate, not a moat — MIT serves that better, and the capture
worth preventing (a proprietary Vilice Console SaaS) is already covered by AGPL on
Vilice Console. **Trade-off accepted:** someone could build a competing control plane on
Vilice without sharing; that's fine — the substrate spreading grows the ecosystem.

## Mechanics

- root `LICENSE` = AGPL-3.0 verbatim from gnu.org, unmodified (Vilice Console + the repo
  overall). GPL-family texts are never edited or prefixed — the copyright line lives in
  `README.md` and in per-file notices, so licence detection stays clean.
- `vilice/LICENSE` = MIT.
- `examples/LICENSE` = MIT. Examples exist to be copied into someone else's app; inheriting
  the root AGPL would make copying one a trap.
- `install.sh` = MIT by SPDX header. It sits at the root but installs the substrate, so the
  repo-overall rule would otherwise give it the wrong licence.
- `blueprint/agora.md` = CC BY-SA 4.0 (noted in the file, which also points readers back to
  the README map).
- **No blanket SPDX sweep** over `vilice/`'s Go or `console/`'s Ruby. The two LICENSE files
  draw that boundary already; headers go only where a directory's licence isn't obvious
  from the nearest LICENSE file.
- `script/`, `audit/`, and the prose in `blueprint/` and `decisions/` stay under the root
  AGPL. Prose under a software licence is slightly odd; a fourth licence costs more to
  explain than the oddity costs.
