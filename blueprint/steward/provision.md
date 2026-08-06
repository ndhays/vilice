# Steward — Provision

Two root-only commands bring a machine into a state where Steward can run apps and
keep an honest record: `harden` (optional) and `prepare` (required). Both are part of
the legible ceiling (invariant 3) — the operator runs them at the box, and no scoped
key can reach them. These two are the **only** root commands; every other Steward
command runs as the unprivileged `steward` user.

**Status:** Canonical. Last touched 2026-08-06.

---

## `steward harden` — optional, runs first

A self-contained, **generic** Ubuntu lockdown. It is a folder of numbered bash steps
(`steward/harden/`), embedded into the binary and run in order; the single signed
binary still carries everything. The steps:

- **ssh** — key-only, no passwords, classic `ssh.service` (Ubuntu's `ssh.socket`
  ignores the `Port` directive). On a fresh root box root stays key-only
  (`prohibit-password`) — *not* locked out, since the two root commands need a way back;
  it's the break-glass. Root login is closed entirely (`PermitRootLogin no`) only when a
  non-root admin account (uid ≥ 1000, login shell, keyed) can already log in by key — so
  the box is never left with no key-based login. The `steward` user is a system account
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
- **Knows nothing about steward.** No steward user, no record, no Podman — it is
  generic box hardening steward merely carries and can invoke (like a dependency), not
  steward-specific setup. That is why it is kept wholly separate from `prepare`: a
  hardened box and an accountable box are two independent claims, neither hiding the
  other. (steward still records the *act* of running it — invariant 2 — but the steps
  themselves are steward-agnostic.)

### `harden --check` — verify the posture, change nothing

`harden --check` asserts the posture the steps apply and reports drift, the way
`verify` asserts the record chain. It runs the generic `harden/check.sh` probe (an
authoritative `sshd -T` / `ufw` read, so it needs root), prints an OK/FAIL line per
property, and exits non-zero (`hardening_drift`) if anything regressed. It is a **read**:
it is *not* recorded (so it works before `prepare` lays the floor) and it changes
nothing. It covers the **generic** posture only — the record floor (`chattr +a`) is
`prepare`'s contract, not harden's.

Both `harden` (on a successful apply) and `harden --check` **publish the result** to
`/var/lib/steward/hardening.json` (root-written, `0644`). That file is a **status-lane
fact**, not part of the audit chain — the bridge that lets the unprivileged observe path
see a root-only posture: the privileged side writes the fact, `status` reads it (see
[record.md](record.md)). Steward Console surfaces it as a hardening line; an absent file
reads as "never checked".

## `steward prepare <role>` — required, and says what the box is for

Installs what Steward drives, and lays the accountability floor. **The role is required**:

```
steward prepare host        # runs apps: Podman, restic, Caddy; opens 80/443
steward prepare balancer    # fronts other boxes: Caddy only; opens 80/443
```

The role is the **first** argument — `prepare host --yes`, never `prepare --yes host`.
Flag parsing takes the token after a flag as that flag's value, so a leading `--yes` would
swallow the role and prepare nothing; requiring it first makes the parse unambiguous
rather than surprising. Bare `steward prepare` is an error. A box exists to do something, and saying which costs
one word and makes the answer to "what is this machine for" a recorded fact rather than an
inference from what happens to be installed. There are exactly two roles because there are
exactly two things a box does here; a third arrives when a third is real, not for symmetry.

- **The role is written to `/var/lib/steward/role`** (root-owned, one word) and **recorded
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
- **The `steward` user:** created here, with subuid/subgid ranges and `enable-linger` so
  its rootless containers and `systemctl --user` units run at boot without a login. Apps
  deploy as this user, not root — see [auth.md](auth.md) and
  [`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).
- **Caddy routing:** the system Caddy (root, on :80/:443) is pointed at a steward-owned
  fragment directory (`/etc/caddy/steward/*.caddy`); deploys write `apps.caddy` and
  `route` writes `routes.caddy`, both reloading via Caddy's local admin API, so no root is
  needed in either loop. Both roles get this — it is what a balancer *is*.
- **The role's ports:** `prepare` opens 80/443 for both current roles. It does this only
  when UFW is present and active — **`prepare` never installs or enables a firewall**,
  because that is `harden`'s job and `harden` is optional. A box prepared without hardening
  is still fully accountable; it simply has no firewall to open a hole in.
- **The OS-update grant:** `apply-updates` is operate-scoped (so a scoped key can issue
  it) but apt needs root — the one operate command that does. `prepare` lays a *narrow*
  `/etc/sudoers.d/steward` (`visudo`-validated, `0440`) letting the `steward` user run
  exactly `apt-get update -y` and `apt-get upgrade -y` as root, nothing else. The ceiling
  stays small and legible — the grant is as inspectable as `authorized_keys`. See
  [`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).
- **The accountability floor:** create the append-only, hash-chained record and
  protect it so nothing later can quietly rewrite it (see [record.md](record.md)).
  This is the one thing `prepare` must get right; it is why the floor lives here. The
  `snapshot` timer runs as the `steward` user so it sees the rootless app containers.
- **The packs prepare themselves.** After the floor is laid, `prepare` calls each
  registered pack's `Prepare()`, which installs and configures that pack's own
  substrate — for `steward-app`, Podman, restic, and Caddy plus its routing. The
  ceiling never learns what was installed. What the operator is consenting to is
  aggregated from every pack and shown in **one** prompt before anything runs. See
  [packs.md](packs.md).
- **The pack authorization:** create the root-owned shelf `/usr/libexec/steward/` and
  write `/etc/steward/packs.manifest`, naming each pack this binary carries at the
  binary's own digest — and record each authorization in the chain. Until the manifest
  exists no packed verb runs, so this is part of the floor, not a nicety. Both paths
  are root-owned, which is the enforcement: the `steward` user reads them and cannot
  write them, so no scoped key can widen what may run. See [packs.md](packs.md).
- **Steward's own secrets** live in `/var/lib/steward/secrets/` (steward-owned, `0700`) —
  *not* `/etc` or `/root`, since everything but `prepare`/`harden` runs as the `steward`
  user. The backup repo password is its first occupant; encrypted-at-rest custody
  (age/`pass`) is a later upgrade that wraps this whole dir.
- **Idempotent.** Safe to re-run; a second run converges, it does not double up.
- **Asks first.** Before installing, it shows an apt-style "about to install …"
  summary and waits for confirmation; `--yes` skips the prompt for automation. Both
  `prepare` and `harden` end with a completion banner (OS, what's in place, next step).

After `prepare`, the box can accept scoped keys ([auth.md](auth.md)) and run deploys
([deploy.md](deploy.md)).

## Upgrading an installed Steward

There is no `steward upgrade`, deliberately (see [Why this is the ceiling](#why-this-is-the-ceiling)).
An upgrade is the two steps that already exist, run as root on the box:

1. **Replace the binary through the signed channel** — `install.sh <version>`, which
   verifies an ed25519 signature *before* installing and fetches the public key from a
   different host than the binary, so no single server hands you both. It overwrites in
   place safely, even while a command is running.
2. **`steward prepare`** — idempotent, so it converges whatever the new version added
   (units, the sudoers grant, directory modes) and skips what is already right.

**Install to the same path.** The binary's absolute path is baked into two places: the
snapshot unit's `ExecStart`, and the forced command of *every* scoped key. Step 2
rewrites the unit, but nothing rewrites a key's line except `authorize` — so landing the
binary somewhere new leaves every scoped key aimed at a file that isn't there, and the
only repair is re-authorizing every client. `doctor` compares its own path against both
and says so when they diverge, because otherwise the first symptom is Steward Console
silently unable to reach the box.

Nothing running stops during an upgrade: apps are ordinary Quadlet units and Steward is
not a daemon, so replacing the binary changes only what happens on the *next* invocation.

---

## `steward uninstall` — the inverse of `prepare`

Root-only, like `prepare`, and never reachable over a scoped key — the gate cannot
remove its own gate. It takes off exactly what `prepare` put on for the *gate and the
scribe*: the snapshot timer, the scoped-key ledger (`authorized_keys`), the OS-update
sudoers grant, the pack manifest, and the binary. Withdrawing the manifest is what
stops the packs — the same move as removing the ledger rather than the keys. The shelf
itself is left alone: an empty directory is harmless, and anything an operator put
there is theirs. **Apps keep running** — they are ordinary Quadlet units
under systemd with plain Caddy routes and need no Steward; removing them too is an
explicit choice (`--remove-apps`, or the y/N prompt when apps exist), executed through
`steward remove` *as the steward user* so teardown never touches root's Podman world.

What stays, on purpose: the `steward` user and `/var/lib/steward` — the record is the
box's history and outlives the tool. Before anything is removed it surfaces the restic
repo and **where its password is** — the backups outlive the box, and without the
password they are unreadable. It prints the path, never the secret: the file survives
uninstall, so nothing is lost by making the operator run one more command, while printing
it would spend it into scrollback, the journal, and any `--yes` automation log. One
confirm gates the whole thing (`--yes` for automation); declined means nothing happened.
Why this shape and not a full `decommission`:
[decisions/uninstall-removes-the-gate.md](../../decisions/uninstall-removes-the-gate.md).

## Why this is the ceiling

`harden`, `prepare`, and `uninstall` change the box itself, so they need root and no
scoped key can reach them — enforced by filesystem ownership rather than a check that
could be bypassed. Replacing Steward itself stays *below* Steward — systemd plus the god-key
bootstrap — never through it.

The ceiling is the **machine and the record**, not the rights ledger. `authorize`/`revoke`
only edit steward's own `authorized_keys`, so they run as the `steward` user and sit at
the top of the scope ladder, not in this root tier — see [auth.md](auth.md) and
[decisions/ceiling-is-the-machine.md](../../decisions/ceiling-is-the-machine.md).

## Open

Open questions for provisioning are kept out of the spec, in
[`steward-open-questions.md`](../../decisions/open/steward-open-questions.md) — the
dependency set beyond Podman and Caddy (backup engine, off-host shipping). (The container
user model is now settled: deploys are rootless under the `steward` user — see
[`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md) and
[`quadlet-deploy.md`](../../decisions/quadlet-deploy.md).) When one settles, its answer
moves into this spec and its reasoning into `decisions/`.
