# Vilice — Provision

Two root-only commands bring a machine into a state where Vilice can run apps and
keep an honest record: `harden` (optional) and `prepare` (required). Both are part of
the legible ceiling (invariant 3) — the operator runs them at the box, and no scoped
key can reach them. These two are the **only** root commands; every other Vilice
command runs as the unprivileged `_vilice` user.

**Status:** Canonical. Last touched 2026-08-06.

---

## `vilice harden` — optional, runs first

A self-contained, **generic** Ubuntu lockdown. It is a folder of numbered bash steps
(`vilice/harden/`), embedded into the binary and run in order; the single signed
binary still carries everything. The steps:

- **ssh** — key-only, no passwords, classic `ssh.service` (Ubuntu's `ssh.socket`
  ignores the `Port` directive). On a fresh root box root stays key-only
  (`prohibit-password`) — *not* locked out, since the two root commands need a way back;
  it's the break-glass. Root login is closed entirely (`PermitRootLogin no`) only when a
  non-root admin account (uid ≥ 1000, login shell, keyed) can already log in by key — so
  the box is never left with no key-based login. The `_vilice` user is a system account
  (uid < 1000) and never trips this; it's irrelevant to the root-login decision.
- **firewall** — UFW (deny inbound, allow outbound, **allow sshd's port and nothing
  else**) and fail2ban (ban repeated sshd auth failures). The port allowed is the one
  `sshd` is actually configured for, never the constant 22 — a rule that assumes 22 locks
  you out of a box reached on 2222, and a remote lockout is unrecoverable. Rules are added
  *before* UFW is enabled, for the same reason. **Web ports are not harden's business**:
  80/443 are opened by `prepare <role>`, because whether a box serves web is a fact about
  its role, not about its lockdown.
- **unattended-upgrades** — automatic *security* patches, with a reboot window. Full
  upgrades stay deliberate (`apply-updates`).
- **swap** and **persistent journald**.

Three properties define it:

- **Optional.** A box is fully accountable without it.
- **First**, before `prepare`, when used.
- **Knows nothing about vilice.** No _vilice user, no record, no Podman — it is
  generic box hardening vilice merely carries and can invoke (like a dependency), not
  vilice-specific setup. That is why it is kept wholly separate from `prepare`: a
  hardened box and an accountable box are two independent claims, neither hiding the
  other. (vilice still records the *act* of running it — invariant 2 — but the steps
  themselves are vilice-agnostic.)

### `harden --check` — verify the posture, change nothing

`harden --check` asserts the posture the steps apply and reports drift, the way
`verify` asserts the record chain. It runs the generic `harden/check.sh` probe (an
authoritative `sshd -T` / `ufw` read, so it needs root), prints an OK/FAIL line per
property, and exits non-zero (`hardening_drift`) if anything regressed. It is a **read**:
it is *not* recorded (so it works before `prepare` lays the floor) and it changes
nothing. It covers the **generic** posture only — the record floor (`chattr +a`) is
`prepare`'s contract, not harden's.

Both `harden` (on a successful apply) and `harden --check` **publish the result** to
`/var/lib/vilice/hardening.json` (root-written, `0644`). That file is a **status-lane
fact**, not part of the audit chain — the bridge that lets the unprivileged observe path
see a root-only posture: the privileged side writes the fact, `status` reads it (see
[record.md](record.md)). Vilice Console surfaces it as a hardening line; an absent file
reads as "never checked".

## `vilice prepare <role>` — required, and says what the box is for

Installs what Vilice drives, and lays the accountability floor. **The role is required**:

```
vilice prepare host        # runs apps: Podman, restic, Caddy; opens 80/443
vilice prepare balancer    # fronts other boxes: Caddy only; opens 80/443
```

The role is the **first** argument — `prepare host --yes`, never `prepare --yes host`.
Flag parsing takes the token after a flag as that flag's value, so a leading `--yes` would
swallow the role and prepare nothing; requiring it first makes the parse unambiguous
rather than surprising. Bare `vilice prepare` is an error. A box exists to do something, and saying which costs
one word and makes the answer to "what is this machine for" a recorded fact rather than an
inference from what happens to be installed. There are exactly two roles because there are
exactly two things a box does here; a third arrives when a third is real, not for symmetry.

- **The role is written to `/var/lib/vilice/role`** (root-owned, one word) and **recorded
  in the chain** — so "what was this box prepared as, by whom, when" is answerable from the
  record. The file is what `status` reports and what `deploy` checks; the record is the
  history of it.
- **Re-preparing with a *different* role is an error.** Converting a host that is running
  apps into a balancer by re-running one command is exactly the silent surprise this
  project avoids. Re-running the *same* role is idempotent, as before.
- **`deploy` refuses on a balancer**, naming the reason — a balancer has no Podman, and
  "podman: not found" is a worse answer than "this box was prepared as a balancer."
- **Substrate follows the role.** The operator is shown one apt-style summary of what that
  role installs, and nothing else is installed. A balancer that carried Podman and restic
  it would never use is surface to patch for no benefit.

- **Dependencies, by role:** a **host** gets Podman (containers), restic (backups), and
  Caddy (routing); a **balancer** gets Caddy alone. These are deliberate, fixed choices,
  not incidental packages. Quadlet needs **Podman ≥ 4.4**
  (`doctor` asserts it); `doctor` also checks restic is present.
- **The `_vilice` user:** created here, with subuid/subgid ranges and `enable-linger` so
  its rootless containers and `systemctl --user` units run at boot without a login. Apps
  deploy as this user, not root — see [auth.md](auth.md) and
  [`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).
- **Caddy routing:** the system Caddy (its own `caddy` user, on :80/:443) is pointed at a
  vilice-owned fragment directory (`/etc/caddy/vilice/*.caddy`); deploys write
  `apps.caddy` and `route` writes `routes.caddy`, both reloading via Caddy's admin socket,
  so no root is needed in either loop. Both roles get this — it is what a balancer *is*.
- **Caddy's admin socket:** the admin API listens on `/run/caddy-admin/admin.sock`, never
  on `localhost:2019`, where any local user could replace Caddy's config. The directory
  is `caddy:vilice 2750` (recreated each boot by `/etc/tmpfiles.d/caddy-admin.conf`), and
  the socket is `0220` in the _vilice group — so the caddy user and the _vilice user can
  reach it, and nobody else can. `doctor` checks both halves: the socket opens, and
  nothing answers on 2019. See
  [`caddy-admin-socket.md`](../../decisions/caddy-admin-socket.md).
- **The role's ports:** `prepare` opens 80/443 for both current roles. It does this only
  when UFW is present and active — **`prepare` never installs or enables a firewall**,
  because that is `harden`'s job and `harden` is optional. A box prepared without hardening
  is still fully accountable; it simply has no firewall to open a hole in.
- **The OS-update grant:** `apply-updates` is operate-scoped (so a scoped key can issue
  it) but apt needs root — the one operate command that does. `prepare` lays a *narrow*
  `/etc/sudoers.d/vilice` (`visudo`-validated, `0440`) letting the `_vilice` user run
  exactly `apt-get update -y` and `apt-get upgrade -y` as root, nothing else. The ceiling
  stays small and legible — the grant is as inspectable as `authorized_keys`. See
  [`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).
- **The accountability floor:** create the append-only, hash-chained record and
  protect it so nothing later can quietly rewrite it (see [record.md](record.md)).
  This is the one thing `prepare` must get right; it is why the floor lives here. The
  `snapshot` timer runs as the `_vilice` user so it sees the rootless app containers.
- **The app layer prepares itself.** After the floor is laid, `prepare` calls the app
  layer's `Prepare(role)`, which installs and configures its own substrate — for a
  `host`, Podman, restic, and Caddy plus its routing; for a `balancer`, Caddy alone.
  The ceiling never learns what was installed. What the operator is consenting to is
  shown in **one** prompt before anything runs.
- **The binary authorization:** write `/etc/vilice/binary.digest`, naming this
  binary's own sha256 — and record the authorization in the chain. Until it exists no
  verb that acts runs, so this is part of the floor, not a nicety. The path is
  root-owned, which is the enforcement: the `_vilice` user reads it and cannot write
  it, so no scoped key can authorize a different binary. Swap the binary and every
  verb that acts refuses, with the refusal recorded.
- **Vilice's own secrets** live in `/var/lib/vilice/secrets/` (vilice-owned, `0700`) —
  *not* `/etc` or `/root`, since everything but `prepare`/`harden` runs as the `vilice`
  user. The backup repo password is its first occupant; encrypted-at-rest custody
  (age/`pass`) is a later upgrade that wraps this whole dir.
- **Idempotent.** Safe to re-run; a second run converges, it does not double up.
- **Asks first.** Before installing, it shows an apt-style "about to install …"
  summary and waits for confirmation; `--yes` skips the prompt for automation. Both
  `prepare` and `harden` end with a completion banner (OS, what's in place, next step).

After `prepare`, the box can accept scoped keys ([auth.md](auth.md)) and run deploys
([deploy.md](deploy.md)).

## Upgrading an installed Vilice

There is no `vilice upgrade`, deliberately (see [Why this is the ceiling](#why-this-is-the-ceiling)).
An upgrade is the two steps that already exist, run as root on the box:

1. **Replace the binary through the signed channel** — `install.sh <version>`, which
   verifies an ed25519 signature *before* installing and fetches the public key from a
   different host than the binary, so no single server hands you both. It overwrites in
   place safely, even while a command is running.
2. **`vilice prepare`** — idempotent, so it converges whatever the new version added
   (units, the sudoers grant, directory modes) and skips what is already right.

**Install to the same path.** The binary's absolute path is baked into two places: the
snapshot unit's `ExecStart`, and the forced command of *every* scoped key. Step 2
rewrites the unit, but nothing rewrites a key's line except `authorize` — so landing the
binary somewhere new leaves every scoped key aimed at a file that isn't there, and the
only repair is re-authorizing every client. `doctor` compares its own path against both
and says so when they diverge, because otherwise the first symptom is Vilice Console
silently unable to reach the box.

Nothing running stops during an upgrade: apps are ordinary Quadlet units and Vilice is
not a daemon, so replacing the binary changes only what happens on the *next* invocation.

---

## `vilice uninstall` — the inverse of `prepare`

Root-only, like `prepare`, and never reachable over a scoped key — the gate cannot
remove its own gate. It takes off exactly what `prepare` put on for the *gate and the
scribe*: the snapshot timer, the scoped-key ledger (`authorized_keys`), the OS-update
sudoers grant, the binary authorization (`/etc/vilice/binary.digest`), and the
binary. Withdrawing the authorization is what stops a binary left behind by hand —
the same move as removing the ledger rather than the keys. **Apps keep running** —
they are ordinary Quadlet units
under systemd with plain Caddy routes and need no Vilice; removing them too is an
explicit choice (`--remove-apps`, or the y/N prompt when apps exist), executed through
`vilice remove` *as the _vilice user* so teardown never touches root's Podman world.

What stays, on purpose: the `_vilice` user and `/var/lib/vilice` — the record is the
box's history and outlives the tool — and the substrate, since **uninstall removes no
packages**: they may serve the apps that keep running, and removing another tool's
substrate is not the gate's call.

The ceiling does not name that substrate. It prints what *it* keeps and then asks the
app layer for the rest (`TeardownNote`), because the app layer is what installed it and
what knows this box's role — a fixed list in the ceiling told a `balancer` it was
keeping Podman and restic, which it never had. The same note surfaces the restic repo
and **where its password is** — the backups outlive the box, and without the password
they are unreadable. It prints the path, never the secret: the file survives uninstall,
so nothing is lost by making the operator run one more command, while printing it would
spend it into scrollback, the journal, and any `--yes` automation log. One confirm gates
the whole thing (`--yes` for automation); declined means nothing happened.
Why this shape and not a full `decommission`:
[decisions/uninstall-removes-the-gate.md](../../decisions/uninstall-removes-the-gate.md).

## Why this is the ceiling

`harden`, `prepare`, and `uninstall` change the box itself, so they need root and no
scoped key can reach them — enforced by filesystem ownership rather than a check that
could be bypassed. Replacing Vilice itself stays *below* Vilice — systemd plus the god-key
bootstrap — never through it.

The ceiling is the **machine and the record**, not the rights ledger. `authorize`/`revoke`
only edit vilice's own `authorized_keys`, so they run as the `_vilice` user and sit at
the top of the scope ladder, not in this root tier — see [auth.md](auth.md) and
[decisions/ceiling-is-the-machine.md](../../decisions/ceiling-is-the-machine.md).

## Open

Open questions for provisioning are kept out of the spec, in
[`vilice-open-questions.md`](../../decisions/open/vilice-open-questions.md) — the
dependency set beyond Podman and Caddy (backup engine, off-host shipping). (The container
user model is now settled: deploys are rootless under the `_vilice` user — see
[`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md) and
[`quadlet-deploy.md`](../../decisions/quadlet-deploy.md).) When one settles, its answer
moves into this spec and its reasoning into `decisions/`.
