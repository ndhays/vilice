---
title: Docs
nav: docs
---
# Steward

**Contents:** [Proof Of Concept](#a-proof-of-concept) &middot; [Install](#install) &middot; [Upgrade](#upgrade) &middot; [Authentication](#authentication--scoped-ssh) &middot; [The Ceiling](#the-ceiling) &middot; [Build From Source](#build-from-source)

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
verbs that [run apps](/apps.html) sit on the other side of one line inside the same
binary. `prepare` writes down the binary's own digest, and every verb that acts checks
the running executable against it — swap the binary and Steward refuses, in the record.

You rarely type any of this. [Steward Console](/console.html) drives it over scoped SSH,
running these same commands. It is also the breakglass surface: the operator always has it
over their own SSH, so recovery never depends on the web UI.

> **Every command has a page.** [The command reference](/commands/) is generated from the
> binary — each page opens with that command's real `--help` output, so it cannot say
> anything the CLI does not. Or just run `steward help`.

## A Proof Of Concept

Most of the code in this project was **written by an LLM**, from a specification that came
first and is still the canonical artifact — the blueprint is prose, and the code is a
projection of it. Saying so plainly is more useful than letting a reader work it out from
the commit history.

It has a consequence worth stating. [Codeberg's Terms of Use](https://codeberg.org/Codeberg/org/src/branch/main/TermsOfUse.md)
prohibit projects that mostly consist of generative-AI-written code, and this one does — so
the repository lives on GitHub, and what is published today is a **proof of concept**: the
thing that proved the design works, not the thing meant to be trusted forever.

The intention is to **rewrite the Steward core by hand** from that same specification and
host it on Codeberg, with an LLM as **editor and critic only** — reviewing code a human
wrote, never writing it. The reason is ownership rather than optics: retyping does not
change where code came from, but human authorship is what makes a licence mean anything,
and a copyleft over code nobody can own is a weak instrument for a project whose whole
argument is sovereignty.

Until then: read the design, run it on a box you can afford to lose, and judge the idea
rather than the artifact.

## Install

> **You don't have to install Steward yourself.** Steward Console installs and drives it for
> you — point the app at a box and it handles the machine layer. The walkthrough here is
> for digging under the hood by hand.

**Install the CLI.** One command downloads the binary, **verifies its signature**, and
installs it:

```bash
curl -fsSL https://steward.agoraforge.org/install.sh | sudo bash -s -- 0.2.0beta
```

<details>
<summary>Or verify the signature by hand first</summary>

Confirm the binary is genuinely the published one before running it as root. The check
matches the release tarball against its ed25519 signature with our public key — and you
fetch that key from the **source repository on GitHub**, a *different* host than the
release server, so no single compromised server can hand you a matching key and binary
at once:

```bash
V=0.2.0beta
base=https://steward.agoraforge.org/releases/steward/$V/steward-linux-amd64.tar.gz

# the binary + its signature, from the release host
curl -fsSLO "$base"
curl -fsSLO "$base.sig"

# the public key, from the source repo (a different provider)
curl -fsSL https://raw.githubusercontent.com/ndhays/steward/main/steward/release-key.pub -o release-key.pub

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
sudo steward harden          # optional OS lockdown — key-only SSH, UFW, fail2ban
sudo steward prepare host    # say what the box is for; installs what that needs
sudo -iu steward             # cross the seam once; everything past here runs as this user
```

**Admit a key.** Authorize the actor that will operate the box — Steward Console, or your own
automation — at a scope:

```bash
steward authorize "ssh-ed25519 AAAA… console@host" --client console --scope operate
```

From there, every deploy happens over scoped SSH. The next thing you need is an
[AppConfig](/apps.html#appconfig), and then [`steward deploy`](/commands/deploy.html).

## Upgrade

There is no `steward upgrade` command. Upgrading is the same signed install, pointed at
a newer version, followed by `prepare`:

```bash
curl -fsSL https://steward.agoraforge.org/install.sh | sudo bash -s -- 0.2.0beta
sudo steward prepare host --yes
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

See [`authorize`](/commands/authorize.html), [`revoke`](/commands/revoke.html), and
[`actors`](/commands/actors.html).

## The Ceiling

Three commands are **root-only**, run by the operator on the box itself: they change the
*machine*. They are *not* reachable through any scoped key — the gate cannot re-provision,
replace, or remove itself. This small, enumerable set, together with the append-only record,
is the **legible ceiling** the operator audits by eye. Everything else runs as the
unprivileged `steward` user.

- [`harden`](/commands/harden.html) — optional OS and `sshd` lockdown. Kept separate from
  `prepare` on purpose: the accountability floor never lives here, so a box is accountable
  even un-hardened.
- [`prepare`](/commands/prepare.html) — say what the box is for, install what that role
  needs, lay the record.
- [`uninstall`](/commands/uninstall.html) — remove the gate and the scribe. **Your apps
  keep running.**

Steward is not a runtime — apps run under systemd with plain Caddy routes — so `uninstall`
stops nothing unless you ask it to. Retiring the hardware entirely (wipe secrets, remove
the user, decide the backups' fate) is a separate, deliberate act; uninstall points the way.

Everything else — deploy, lifecycle, backups, reads — runs as the unprivileged `steward`
user over scoped SSH, audited before it executes. [See every command](/commands/).

## Build From Source

Work on Steward from source — it lives in the [monorepo](https://github.com/ndhays/steward)
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
make man      # steward(1), generated from the same command table as --help
```
