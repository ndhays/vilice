# Security audit — how the posture is measured

> Settles the security smoke-tests thread in
> [`open/vilice-open-questions.md`](open/vilice-open-questions.md). The readings are in
> [`audit/log.md`](../audit/log.md).

## Three audits

- **Code** — `govulncheck` + `gosec` over the Go. `make audit`.
- **Box posture** — `ssh-audit` + `nmap` + `Lynis` against a prepared, hardened box.
  Proves `harden/` did what it claims. `make audit-box HOST=…`.
- **Gate** — adversarial tests over Vilice's own boundary: `gate_test.go` (who may reach
  what) and the inject tests (what a value may become once rendered). `go test`, plus
  `make fuzz`.

The first two measure the toolchain and the box. Neither measures the gate. The
2026-08-01 audit found six live findings there: nothing had ever handed Vilice a hostile
string.

The gate tests are **properties over the commands table**, not cases — "every command
whose synopsis takes an `<app>` refuses a traversal name" covers the command added next
month. Every finding in that audit began as a check written once and missed in the other
places that needed it. Failing fuzz inputs are checked into `testdata/fuzz/` as permanent
regression tests.

## What runs when

- **`make check` runs on every push** (`.github/workflows/ci.yml`): formatted, vetted,
  tested. CI was once manual on purpose; that stopped holding when a rename shipped a
  wrong account name in `prepare` that nothing ran unasked.
- **`make audit` gates `release`, not `build`.** It needs the network and is slow. A
  govulncheck finding usually means the toolchain is behind: bump Go.
- **`release` depends on `audit-entry`**, which refuses a version with no entry in
  `audit/log.md`. The scans ran on every release from 0.2 to 0.4.1 and nobody recorded
  what they said.

## gosec policy

Vilice shells out and writes system files at deliberate permissions, so
**G301/G302/G304/G306** fire on choices that are correct: the record is world-readable on
purpose (observe is zero-privilege), systemd units are `0644`, and every "tainted" path
is Vilice's own configured path. Those four are excluded (`vilice/Makefile`).

**G204 (subprocess) stays on**, annotated at each call site with why the input is
trusted. The annotation is the audit.

**A pin bump is an audit of its own.** Moving gosec to v2.29.0 on 2026-09-29 reached
three exec helpers never annotated. Two were safe. The third takes app names, and
`ValidAppName` allowed a leading dash — an app named `-H` would have been passed to
`systemctl` as a flag. The rule now requires an alphanumeric first character, and the
console's `NAME_FORMAT` moved with it.

## The on-box check is native

`ssh-audit` is a large Python tool around a cipher policy database that changes
constantly. Reimplementing it means chasing that policy; shelling out adds a runtime
dependency and breaks the single static binary. The scanners stay external.

What is built in is `harden --check`, running `harden/check.sh` — a dependency-free check
of Vilice's own hardening contract.

## Root writes the fact, observe reads it

`harden --check` needs root (`sshd -T`, `ufw`). The console's observe path is `_vilice`.
Observe is **not** escalated. Root publishes a fact (`/var/lib/vilice/hardening.json`,
`0644`) and `status` reads it. The fact carries `checked_at`, so staleness is visible.

`harden --check` is a read: it is not recorded, and it works before `prepare`. It stays
out of `doctor`, which runs as `_vilice` and answers "ready to deploy?"; `doctor` prints
a pointer.

## Roads not taken

- **OpenSCAP.** Enterprise compliance machinery with weak Ubuntu content. `Lynis` covers
  the ground. Revisit if a formal CIS profile is required.
- **Trivy / testssl.sh.** Deferred. Trivy belongs on the console image; `testssl.sh`
  needs a real certificate.
- **A stored "hardened at" timestamp.** A stamp drifts from reality: re-enable root SSH
  and it still says hardened.
