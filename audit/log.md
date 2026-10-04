# Audit log

The security-audit attestation, one entry per released version — `make release` refuses
a version that has none. This is the committed
verdict — the "this version was measured" record. Raw scanner output (`out/`) is
regenerable and gitignored; only the human reading lives here.

How the numbers are produced:

- **Code** — `make audit` (govulncheck + gosec). A govulncheck finding usually means the
  build toolchain is behind: bump Go to the latest patch release and re-run.
- **Box** — `make audit-box HOST=<box>` (ssh-audit + nmap + Lynis against a
  prepared+hardened box). Fold regressions back into `harden/`; the live on-box guard is
  `vilice harden --check`.

See [`decisions/security-audit.md`](../decisions/security-audit.md) for the why.

---

## Template (copy for each version)

```
## vX.Y.Z — YYYY-MM-DD

Code (make audit)
- govulncheck: <clean | N findings — remediation>
- gosec:       <clean (policy: G301/G302/G304/G306 excluded; G204 annotated) | N findings>
- toolchain:   go<version>

Box (make audit-box HOST=<box>)
- ssh-audit:   <grade / notes>
- open ports:  <set>   (expected 22,80,443)
- lynis index: <N>
- harden --check: <hardened | drift: …>

Folded into harden/: <changes, or none>
```

---

<!-- newest entries on top -->

## v0.4.2 — 2026-10-04

Code (make audit)
- govulncheck: **clean** — "No vulnerabilities found."
- gosec:       **clean** (policy: G301/G302/G304/G306 excluded; G204 annotated)
- toolchain:   go1.27.1 (the `toolchain` floor in go.mod is go1.26.6)

Box (make audit-box HOST=<box>)
- **Not run.** No ssh-audit, nmap or Lynis baseline has been captured for any version;
  it is still the open item in `decisions/open/vilice-open-questions.md`.
- harden --check: not read for this entry.

Folded into harden/: none.

## v0.2.0 – v0.4.1 — no entries

Nothing was written for these. `release` depends on `audit`, so every version cut with
`make release` passed govulncheck and gosec at the time — but what they said was not
recorded, and no box audit was run. From v0.4.2 `make release` refuses a version with no
entry here (`audit-entry` in `vilice/Makefile`).

## v0.1.2 — 2026-06-10

Code (make audit)
- govulncheck: **clean** — "No vulnerabilities found."
- gosec:       **clean** (policy: G301/G302/G304/G306 excluded; G204 + G115 annotated)
- toolchain:   go1.26.4 (bumped from 1.22.2, which govulncheck had flagged)

Box (devbox)
- harden --check: **hardened** — root SSH login disabled, password auth disabled,
  firewall active, fail2ban running, unattended upgrades. (Confirmed live.)
- ssh-audit / nmap / Lynis baseline: still to capture via `make audit-box HOST=devbox`.

Folded into harden/: none.
