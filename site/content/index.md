---
title: Documentation
---
# Documentation

**Contents:** [Install](#install) &middot; [Upgrade](#upgrade) &middot; [Authentication](#authentication--scoped-ssh) &middot; [Root Commands](#root-commands) &middot; [Steward Commands](#steward-commands) &middot; [Build From Source](#build-from-source)

Steward is a single Go binary on every machine, and the layer with the privilege. Every
action is a named actor, a declared scope, and a record written before it runs — **there
is no path to the box's power that skips that.** That one property is the whole security
claim, and it is small enough to check.

It is a gate and a scribe, not a runtime. No daemon, no listener, no token; it exists only
while a command runs. Delete the binary and nothing running stops — apps are ordinary
systemd units behind ordinary Caddy config. What stops is the gate and the record.

The record is the one thing Steward does not borrow: a plain append-only file, one JSON
object per line, hash-chained so an edit or a deletion shows. No database, no format you
need a tool to read — `cat` it. `steward verify` walks the chain and reports the first
break.

Steward is layered. A small **core** owns the gate, the record, and the root ceiling; the
verbs live in [packs](/packs.html) it dispatches to, and a pack runs only if the box's
manifest authorizes it by digest. The core is what you have to trust, and it is meant to
stop changing.

You rarely type any of this. [Steward Console](/console.html) drives it over scoped SSH,
running these same commands. It is also the breakglass surface: the operator always has it
over their own SSH, so recovery never depends on the web UI.

## Install

> **You don't have to install Steward yourself.** Steward Console installs and drives it for
> you — point the app at a box and it handles the machine layer. The walkthrough here is
> for digging under the hood by hand.

**Install the CLI.** One command downloads the binary, **verifies its signature**, and
installs it:

```bash
curl -fsSL https://switchyard.agoraforge.org/install.sh | sudo bash -s -- 0.2.0beta
```

<details>
<summary>Or verify the signature by hand first</summary>

Confirm the binary is genuinely the published one before running it as root. The check
matches the release tarball against its ed25519 signature with our public key — and you
fetch that key from the **source repository on Codeberg**, a *different* host than the
release server, so no single compromised server can hand you a matching key and binary
at once:

```bash
V=0.2.0beta
base=https://switchyard.agoraforge.org/releases/steward/$V/steward-linux-amd64.tar.gz

# the binary + its signature, from the release host
curl -fsSLO "$base"
curl -fsSLO "$base.sig"

# the public key, from the source repo (a different provider)
curl -fsSL https://codeberg.org/agoraforge/switchyard-monorepo/raw/branch/main/steward/release-key.pub -o release-key.pub

# verify before trusting
openssl pkeyutl -verify -rawin -pubin -inkey release-key.pub \
  -in steward-linux-amd64.tar.gz -sigfile steward-linux-amd64.tar.gz.sig
#  → Signature Verified Successfully

tar -xzf steward-linux-amd64.tar.gz
sudo install -m 0755 steward /usr/local/bin/steward
```
</details>

**Set up the box.** Two commands as root change the machine, then you drop to the `steward`
user and stay there:

```bash
sudo steward harden     # optional OS lockdown — key-only SSH, UFW, fail2ban
sudo steward prepare    # install Podman + Caddy, create the steward user, lay the record
sudo -iu steward        # cross the seam once; everything past here runs as this user
```

**Admit a key.** Authorize the actor that will operate the box — Steward Console, or your own
automation — at a scope:

```bash
steward authorize "ssh-ed25519 AAAA… console@host" --client console --scope operate
```

From there, every deploy happens over scoped SSH. The next thing you need is an
[AppConfig](/packs.html#appconfig).

## Upgrade

There is no `steward upgrade` command. Upgrading is the same signed install, pointed at
a newer version, followed by `prepare`:

```bash
curl -fsSL https://switchyard.agoraforge.org/install.sh | sudo bash -s -- 0.2.0beta
sudo steward prepare --yes
steward doctor
```

The first command verifies the signature before replacing anything, and overwrites the
binary in place — safe to run even while a command is in flight. The second converges
anything the new version added; `prepare` is idempotent, so re-running it is normal, not
a repair. Then `doctor` confirms the box is consistent.

**Nothing goes down.** Your apps are ordinary systemd units behind Caddy, and Steward is
not a daemon — it exists only while a command runs. Replacing the binary changes what
happens on the *next* invocation and nothing else.

**Keep the install path the same.** `/usr/local/bin/steward` is written into the snapshot
timer and into every authorized key's forced command. `prepare` fixes the timer; nothing
fixes the keys but re-running `authorize` for each client. Install somewhere new and
every scoped key points at a binary that isn't there — `doctor` reports the mismatch, but
it's far easier not to move it.

## Authentication — Scoped SSH

There is no token to store. The **key is the identity** and the **forced command is
the scope**. An operator admits a named actor by writing a pinned `authorized_keys` line.

Scopes form a ladder — a higher scope grants the ones below it: `observe ⊂ operate ⊂ grant`.

- **observe** — read the record (status, logs, verify, record).
- **operate** — deploy and lifecycle.
- **grant** — mint and revoke keys.

**No scope is a shell.** Every key names the command it wants to run, and a key that
sends no command is refused. That is what makes the audit record complete: there is no
grant that lets someone act on the box without an entry being written first.

The top rung was once called `ssh` and did hand out an interactive shell. That shell was
recorded as a *grant* — one `action="shell"` entry — and then everything done inside it
was invisible, which put an asterisk on the whole claim. The rung kept its job and lost
the shell. Keys issued under the old name keep working; `ssh` now reads as `grant`.

Need a real shell on the box? Use your own account. That is a different named actor with
its own trail, not an anonymous session inside the `steward` identity.

`authorized_keys` *is* the rights ledger: `cat` it and you see every actor and its
ceiling — rights declared and inspectable, not ambient. The authenticated key's client
name is what lands in the audit log (`actor="console"`), so the ledger tells Steward Console
apart from a human at the shell.

## Root Commands

Three commands are **root-only**, run by the operator on the box itself: they change the
*machine*. They are *not* reachable through any scoped key — the gate cannot re-provision,
replace, or remove itself. This small, enumerable set, together with the append-only record,
is the **legible ceiling** the operator audits by eye. Everything else runs as the
unprivileged `steward` user.

| Command | Description |
|---|---|
| `steward harden` | Optional OS / `sshd` hardening. Comes first, before `prepare`, but kept **separate** — the accountability floor never lives here, so a box is accountable even un-hardened. |
| `steward harden --check` | Verify the hardening posture and report drift (a read — changes and records nothing); exits non-zero if anything regressed. Publishes the result so `status` — and Steward Console — can show it. |
| `steward prepare [--yes]` | Install Podman + Caddy and lay the **accountability floor** (the append-only record). Shows an apt-style size confirmation first; `--yes` skips it for automation. Required before any deploy. |
| `steward uninstall [--yes] [--remove-apps]` | Remove the gate and the scribe — the snapshot timer, every scoped key, the sudoers grant, the binary. **Your apps keep running** as ordinary systemd services behind Caddy; `--remove-apps` (or the prompt) takes them down first. Keeps the `steward` user and the record, and points at the restic repo and its password file so the backups aren't orphaned. |

Steward is not a runtime — apps run under systemd with plain Caddy routes — so `uninstall`
stops nothing unless you ask it to. Retiring the hardware entirely (wipe secrets, remove
the user, decide the backups' fate) is a separate, deliberate act; uninstall points the way.

It prints *where* the backup password is, never the password itself. The file survives
uninstall, so nothing is lost by making you run one more command — and printing a secret
would spend it into scrollback, the journal, and any `--yes` automation log.

## Steward Commands

Everything else runs as the unprivileged `steward` user, over scoped SSH, audited before it
executes. Granting itself lives here too — `authorize`/`revoke` only edit steward's own
`authorized_keys`, so they need no root, and they are the **top of the ladder**: a
`grant`-scope key can run them, an `observe` or `operate` key cannot.

| Command | Scope | Description |
|---|---|---|
| `steward authorize <pubkey> --client <name> --scope <observe\|operate\|grant>` | grant | Admit a named actor at a scope — writes the forced-command `authorized_keys` line. |
| `steward revoke <client>` | grant | Remove that actor's line. |

### Deploy &amp; Lifecycle

Scoped `operate`. The desired state Steward deploys is an [AppConfig](/packs.html#appconfig).

| Command | Description |
|---|---|
| `steward deploy <app> --image <ref@sha256>` | Deploy an app from a digest-pinned image. Health-checked before it takes traffic; the deployed image is saved as last-good. |
| `steward rollback <app>` | Re-deploy the last-good image. |
| `steward start \| stop \| restart <app>` | Lifecycle control. |
| `steward remove <app>` | Take an app off the box. |
| `steward backup --repo <url>` | One-time: set the restic repo, read the password on stdin, init it. |
| `steward backup <app>` · `--all` · `--machine` | Snapshot an app's volumes + spec (encrypted, via restic), every app, or Steward's own record off-box. |
| `steward restore <app>` · `--machine` | Restore from the latest snapshot, then redeploy the app. |
| `steward apply-updates` | Apply machine OS package updates. |
| `steward registry-login <registry> --username <user>` | Log the box into a private image registry. The password is read on **stdin**, never argv — only the registry and username are recorded. |
| `steward registry-logout <registry>` | Remove the box's login for a registry. |

Images are always **digest-pinned** (`@sha256:…`) — tags aren't stable.

A **private** registry needs a credential. It's a **box credential**, not part of an
app: `registry-login` writes a persistent rootless login that every later pull reuses,
shared across apps and surviving reboots. A pull from a registry the box isn't logged into
fails **loudly and safely** — the running app is untouched — with a message pointing at
`registry-login`. Static credentials (PAT / password / htpasswd) only; short-lived-token
registries (ECR, GCP) want a credential helper, not yet supported.

### Observe &amp; Record

Scoped `observe`. Reads are zero-privilege: the human at the shell uses these, and
Steward Console reads the record the same way.

| Command | Description |
|---|---|
| `steward status` | Machine summary plus installed apps and their state. |
| `steward logs <app> [-n N]` | Tail an app's logs. |
| `steward verify` | Walk the record and confirm the hash chain is intact, or report the first break. |
| `steward record` | Dump the accountable record — every entry plus a chain-integrity check — so a reader (Steward Console) can show the witnessed history and prove it's unbroken. |
| `steward packs` | What code may run on this box, at what digest — and anything the binary carries that the manifest does not authorize. |
| `steward actors` | Who may act on this box, at what scope, with each key's fingerprint — and any line in the ledger Steward did not write, since a hand-added key reaches the box without passing the gate. |
| `steward doctor` | Check prerequisites and surface problems — the tools Steward drives, the record floor, ghost containers from a wrong-user run, and whether the binary still sits where the scoped keys expect it. |
| `steward snapshot` | Write one record point. Not a command you type. |

## Build From Source

Work on Steward from source — it lives in the [monorepo](https://codeberg.org/agoraforge/switchyard-monorepo)
under `steward/`:

```bash
cd steward && make build     # → bin/steward  (Go 1.22+)
```

The binary has **no dependencies** — `go.mod` requires nothing — so a build needs only
Go. The checks:

```bash
make test     # unit tests, plus the gate tests: who may reach what, and what a value
              # may become once rendered into a config file
make fuzz     # runs the fuzz targets past their seed corpus (FUZZTIME=5m for longer)
make audit    # govulncheck + gosec; gates `make release`, so an unaudited version
              # never ships
```
