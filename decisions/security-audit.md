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

## Lynis is read, not obeyed

Lynis scores a box against a general profile, and a number of its suggestions don't fit
this one. Each is either folded into `harden/` or left out here, with the reason, so the
hardening index is explained rather than chased. From the first Debian 13 box
(2026-11-24, index 67, 1 warning, 44 suggestions):

**Folded in.** Kernel settings (KRNL-6000, `harden/25-kernel.sh`), except
`kernel.modules_disabled`, and `rp_filter` loose (2) rather than strict; the unused
protocols dccp, sctp, rds and tipc (NETW-3200); and from SSH-7408 `LogLevel VERBOSE`,
`X11Forwarding no`, `AllowAgentForwarding no`, `ClientAliveCountMax 2` (with an
interval, so it does something) and `TCPKeepAlive no`.

**Left out, and why:**

- **PKGS-7388, the one warning: "no security repository".** A false alarm. Debian 13
  lists repositories in deb822 `.sources` files, which this Lynis doesn't read;
  `trixie-security` is in `debian.sources`.
- **`kernel.modules_disabled=1`.** Stops every module load after boot; Podman, ufw and
  nftables load modules as they go.
- **`rp_filter=1`.** Strict drops real traffic on a box with a private network as well as
  the public one. Loose still drops what no route leads back to.
- **SSH: `AllowTcpForwarding no`, `MaxAuthTries 3`, `MaxSessions 2`, another port.**
  Vilice's keys are `restrict`ed already, and an operator's tunnels are theirs; with no
  passwords, fewer tries mostly locks out someone with several keys loaded; moving the
  port hides nothing from a scan.
- **Passwords (AUTH-9230/9262/9286).** Nobody logs in with one.
- **umask 027 (AUTH-9328).** The record and units are world-readable by design, and the
  caddy user reads route files root writes.
- **GRUB password, separate /home and /var, USB and FireWire storage (BOOT-5122,
  FILE-6310, USB-1000, STRG-1846).** On a cloud VM the provider account is the console.
- **Banners (BANN-7126/7130).** Theatre.
- **apt-listbugs, apt-listchanges (DEB-0810/0811).** They stop and ask; updates here are
  unattended.
- **libpam-tmpdir, debsums, apt-show-versions (DEB-0280, PKGS-7370/7394).** Little gain
  for a change to every session or another tool to keep.
- **Malware scanner, file integrity, auditd, process accounting, sysstat (HRDN-7230,
  FINT-4350, ACCT-9622/9626/9628).** A large surface for what is left: Vilice records its
  own acts, and the digest of the binary a box authorizes.
- **Lynis's own age, DNS domain, unused firewall rules, automation tools (LYNIS,
  NAME-4028, FIRE-4513, TOOL-5002).** Informational.

**Still open:** off-host logs (LOGG-2154) and sandboxing Vilice's own systemd units
(BOOT-5264) — see `decisions/open/vilice-open-questions.md`; and FILE-7524, whose files
weren't captured yet.

## Roads not taken

- **OpenSCAP.** Enterprise compliance machinery with weak Ubuntu content. `Lynis` covers
  the ground. Revisit if a formal CIS profile is required.
- **Trivy / testssl.sh.** Deferred. Trivy belongs on the console image; `testssl.sh`
  needs a real certificate.
- **A stored "hardened at" timestamp.** A stamp drifts from reality: re-enable root SSH
  and it still says hardened.
