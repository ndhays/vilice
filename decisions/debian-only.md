# Debian only

> Decided 2026-11-23, for 0.5.0. The gate is `checkOS` in `vilice/internal/core/provision.go`
> (`prepare`, `harden`) and `vilice/internal/core/harden/00-os.sh` (the steps on their own).

Vilice runs on **Debian 13**, amd64 or arm64, and nothing else. `prepare` and `harden`
refuse any other OS, naming what they found. Before 0.5.0 it was Ubuntu 26.04 (24.04+),
and `harden` only warned on anything else.

## Why Debian

- **What Vilice installs is security-supported.** Podman, passt, fail2ban and restic are
  in Debian's *main*, which the security team covers. On Ubuntu they are in *universe*,
  where Canonical promises no security fixes without Ubuntu Pro. The tools that run the
  containers, ban attackers and hold the backups were the ones with the weakest promise.
- **Boring.** Debian's images carry less to undo: no snap, no Pro or ESM notices, no
  `ssh.socket` turned on by default. Fewer defaults to fight is fewer harden steps.
- **Long enough.** About three years of security support, then Debian LTS to about 2030,
  on both architectures. Ubuntu's LTS runs longer, but a box is rebuilt well before
  either ends.

## Why only one

- **A security claim is only as good as the OS it was measured on.** `harden` says which
  updates install themselves. Ubuntu's origins written onto Debian, or Debian's onto
  Ubuntu, can load cleanly and patch nothing: a box that reports itself hardened and
  isn't. So the check is a refusal, not a warning. A warning is the worst of the three
  options, because it lets that box exist.
- **Two OSes is every harden step twice**, two box audits per release, and docs that say
  "except on…" forever. That is the opposite of a small, legible ceiling.
- **Supporting others matters less than saying plainly what this is.** `harden/` is
  generic and readable; anyone who wants Ubuntu can carry their own copy.

## The update policy changed with it

`harden` used to allow security updates only. On Debian it allows the two origins
Debian's own default does: the security archive and the stable release's point updates.
Debian ships fixes for security issues too minor for an advisory in point releases, so
"security archive only" would leave known, fixed CVEs unpatched. It still excludes
`-updates`, backports and third-party repositories (Caddy's), and it clears the package's
own lists, so the drop-in is the whole policy.

Two things were added once a Debian box showed what was missing:

- **Caddy's repo is allowed too**, by `prepare`, which added it
  (`origin=cloudsmith/caddy/stable`). Caddy is the one program facing the internet, and
  left out its fixes waited for someone to run `apply-updates`. Debian's own Caddy
  (2.6.2, security-supported) was the other way, but it predates the socket permission
  syntax (`|0220`) the admin socket relies on.
- **`needrestart`, automatic.** An installed fix to a library does nothing for a daemon
  still holding the old one, and Debian flags a reboot mostly for kernels. needrestart
  restarts those services after each update; by its own defaults it never restarts
  `user@*.service`, so apps keep running. `harden --check` counts updates as configured
  only when both halves are.

## Roads not taken

- **Keep both.** The cost above, for a choice most users make once.
- **Ubuntu only, with Pro.** Fixes the universe gap with an account and a token on every
  box: a dependency on a vendor's service for the security of the base.
- **Warn, don't refuse.** The worst option; see above.
- **Debian 12 as well.** Its Podman (4.3) is below Quadlet's 4.4.

## A new Debian release

Is a Vilice release: add its `VERSION_ID` to the gate, after a box audit
(`make audit-box`) on it.
