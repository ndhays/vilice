# Audit log

The security-audit attestation, one entry per audited version. This is the committed
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
