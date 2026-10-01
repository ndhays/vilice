# Security

Vilice and Vilice Console are built so that **there is no path to a machine's power that
skips a scoped, recorded invocation.** That single property — un-bypassability — is the
whole security claim; everything below is a consequence of it.

## The model

Three invariants hold throughout the platform:

1. **Every caller is a named actor with a declared scope.** Authentication is scoped
   SSH: the key is the identity, an OpenSSH *forced command* is the scope, and
   `authorized_keys` is the inspectable rights ledger. Scopes form a ladder —
   `observe ⊂ operate ⊂ ssh`.
2. **Every action writes an accountable record before it runs** — append-only,
   hash-chained, and shipped off-host. Nothing privileged happens off the books.
3. **The privileged layer keeps a small, legible ceiling**, enforced by filesystem
   ownership rather than convention. The ceiling is the **machine and the record**: only
   `prepare` and `harden` (which mutate the box) run as root, and no scoped key can reach
   them. Granting (`authorize`/`revoke`) only edits Vilice's own `authorized_keys`, so it
   runs as the unprivileged `_vilice` user at the top of the ladder, governed by the
   ladder rather than the root tier — see
   [`decisions/ceiling-is-the-machine.md`](decisions/ceiling-is-the-machine.md).

Reads are zero-privilege (`observe`); writes are named, scoped, and witnessed
(`operate`).

## Privilege separation — the `_vilice` user

Root is kept out of the day-to-day loop. Apart from `prepare`/`harden`, every command —
deploy, lifecycle, grant, observe — runs as the unprivileged **`vilice`** user, and
Vilice refuses to run them as root. Consequences:

- **Apps are rootless containers.** They run as rootless Podman under `vilice` (systemd
  Quadlet user units), so a container escape lands as an unprivileged user, not root —
  defense in depth, not just policy.
- **The web edge needs no root in the loop.** Caddy runs on :80/:443 as its own `caddy`
  user; Vilice writes only its own routing fragment (`/etc/caddy/vilice/`) and reloads
  via Caddy's **admin socket** (`/run/caddy-admin/admin.sock`). Caddy's default admin
  endpoint, `localhost:2019`, has no authentication — any local user could replace the
  config — so it is moved to a socket that only the caddy user and the `vilice` group can
  open, and `doctor` flags the old port if anything answers on it. See
  [`decisions/caddy-admin-socket.md`](decisions/caddy-admin-socket.md).
- **App secrets stay off the record and off argv.** Declared by name, delivered on stdin
  into Vilice's Podman secret store, and injected as container env — never on the command
  line, never in `podman inspect`, never in the audit record. See
  [`decisions/declarative-deploy.md`](decisions/declarative-deploy.md).

## Hardening the box

`vilice harden` is optional OS lockdown, kept separate from the accountability floor
(`vilice prepare`) so a box is accountable even un-hardened. It installs:

- key-only SSH — password login disabled, applied lockout-safe. On a fresh root box root
  keeps a key-only login (`prohibit-password`) — the break-glass for re-running the two
  root commands. Root SSH is closed entirely (`PermitRootLogin no`) only when a non-root
  admin account (uid ≥ 1000, login shell, keyed) can already log in by key; the `vilice`
  system user (uid < 1000) never triggers this. The root password stays as a console
  break-glass either way;
- a host firewall (UFW) and intrusion mitigation (fail2ban);
- automatic security updates (unattended-upgrades);
- OS, logging, and swap baseline settings.

It is deliberately generic: it knows nothing about Vilice and can stand alone.

## Secrets

Vilice Console stores each machine's SSH private key **encrypted at rest** (Rails Active
Record Encryption), so revoking one box never touches another. Those encryption keys
live in encrypted Rails credentials, unlocked at runtime by the `RAILS_MASTER_KEY`
environment variable — generated per deployment, never committed.

Vilice releases are signed (ed25519); the installer verifies the signature against a
public key fetched from a *different* host than the artifacts, so no single compromised
server can hand you a matching key and binary at once. A version maps to one set of bytes
forever — never republished — and a vulnerable release is fixed forward and yanked with a
record, never overwritten; see [decisions/versioning.md](decisions/versioning.md).

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue. Email
`security@agoraforge.org` with details and steps to reproduce. We will acknowledge your
report and work with you on a coordinated disclosure.
