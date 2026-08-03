# Licensing

**Decided 2026-06-03.** (Confirm before adding the binding LICENSE files / accepting
outside contributions — relicensing later is costly.)

A permissive substrate under a copyleft application:

- **Steward Console (the control plane) → AGPL-3.0.** It is the SaaS-able value surface;
  AGPL's network clause makes hosted forks share their changes back — Agora's "make
  capture expensive," encoded in the license.
- **Steward (the substrate) → MIT.** Steward is deliberately *small and not the moat*
  — the un-bypassable gate that borrows OpenSSH/Caddy. Permissive maximizes adoption
  and trust in the substrate, and AGPL's network clause doesn't fit a CLI anyway (it
  would behave like GPL and only deter embedding). *(Apache-2.0 is the alternative if
  a patent grant is wanted.)*
- **Agora constitution text → CC BY-SA 4.0** — it's a document, not code; separate
  from the code license.

## Open core, private edges

Steward Console is **both** the open project *and* the software the maintainer runs for
their own clients. The platform is open; the maintainer's client-specific config,
secrets, and private integrations are **never in core** — they live as private
config/plugins/env. Keeping that line clean is what makes "open and proprietary" not a
contradiction.

## Road not taken: an all-AGPL monorepo

Considered one license for everything. Rejected: Steward's value is in being a widely
adoptable, auditable substrate, not a moat — MIT serves that better, and the capture
worth preventing (a proprietary Steward Console SaaS) is already covered by AGPL on
Steward Console. **Trade-off accepted:** someone could build a competing control plane on
Steward without sharing; that's fine — the substrate spreading grows the ecosystem.

## Mechanics

- root `LICENSE` = AGPL-3.0 (Steward Console + the repo overall).
- `steward/LICENSE` = MIT.
- `blueprint/agora.md` = CC BY-SA 4.0 (noted in the file).
- SPDX headers or per-directory notes where the boundary isn't obvious.

*(LICENSE files to be added once this split is confirmed.)*
