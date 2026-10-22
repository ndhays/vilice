# The name is Vilice

> Decided 2026-10-01; published 2026-10-02 as `0.4.0`. **Steward → Vilice** everywhere:
> the brand, the binary, the account (`_vilice`), the state dir, the record, the env
> prefix, the unit names. Answers the name question in
> [`open/landscape-scan.md`](open/landscape-scan.md). What is left is under "Still to do".

## Why rename

"Steward" is a common word, and other tools hold it in the CLI namespace — the one place
a clash is not cosmetic. A name on `PATH`, a unix account, or a directory under
`/var/lib` can be held by one thing per box. A tagline fixes findability; it cannot free
those.

The Steward decision said a second rename was ruled out because "verbs are forever".
That did not hold:

- **The record carries verbs, not the binary name.** `deploy`, `backup`, `rollback`
  survive a rename. The name lives in the forced command, the account, the paths and the
  env vars — tied to an install, not to history.
- **There was no install base.** One dev box.

## The decision

**`vilice`.** Horace's *Epistles* 1.14 is a letter to the steward of his Sabine farm:
*"Vilice silvarum et mihi me reddentis agelli"*. *Vilice* is the form of address of
*vilicus*, the Roman estate steward, who ran the land on the owner's behalf, under a set
remit, and answered for it.

| Where | Was | Becomes |
|---|---|---|
| Brand, product copy | Steward | Vilice |
| Binary, forced command | `steward` | `vilice` |
| Unix account | `steward` | `_vilice` |
| State dir, record | `/var/lib/steward` | `/var/lib/vilice` |
| Env vars | `STEWARD_*` | `VILICE_*` |
| Units, networks, timers | `steward-<name>` | `vilice-<name>` |
| Console product copy | Steward Console | Vilice Console |
| Console Rails module | `StewardConsole` | `ViliceConsole` (directory stays `console/`) |

**The account is `_vilice`.** It is still the product's name, so the box does not
disagree with itself. The underscore marks a service account — the OpenBSD and macOS
convention (`_sshd`, `_www`), followed by newer Debian accounts (`_apt`). Directories
take no prefix.

Two naming rules, because the record makes names permanent:

- **Name by domain, not substrate.** `vilice-backup`, never `vilice-restic`.
- **Verbs stay flat, plain, and forever.** `vilice deploy` must mean the same thing in
  2032.

## Why a coined word passes here

It breaks the naming rule in [`CLAUDE.md`](../CLAUDE.md) on purpose. A word the reader
already owns is a word someone else already uses, and the product's name has to be unique
on every box.

- **It is free where a clash bites** — no binary, account, or package by that name.
- **It is one string.** An agent reading "steward" in a log has to work out which one.
- **One sentence explains it** — Horace's letter to his farm steward.

The rule still holds for everything below the product name.

## The collision scan, 2026-10-01

- **On the box:** no `vilice` binary, account or group; no package in apt, Debian or AUR.
- **Registries:** free on crates.io, npm, PyPI, RubyGems, Homebrew, the Go module proxy,
  Docker Hub and Codeberg.
- **GitHub:** the user `vilice` is an empty account from 2021, so `github.com/vilice` is
  not ours. Never link it.
- **Companies and products:** none found.
- **Trademark:** no exact mark; nearest US marks are VILICO, VILICERT, VILI. Not a legal
  opinion.

## Domains

| Host | Serves |
|---|---|
| `vilice.org` | The site and docs. |
| `get.vilice.org` | `install.sh` and the release binaries. Nothing else. |
| `vilice.com` | Redirects to `vilice.org`. **Never serves `install.sh`.** |
| `github.com/ndhays/vilice` | The source. Personal on purpose. **Never in the trust path.** |
| `codeberg.org/vilice/vilice` | The release public key only, at `release-key.pub`. |

- **Source on GitHub, key on Codeberg.** Codeberg's terms restrict generative-AI code
  ([`the-core-is-handwritten.md`](the-core-is-handwritten.md)); a public key is not code.
  The key then sits on neither the host that serves the binary nor the one that holds the
  source, so no one account can change what a release is and the key that vouches for it.
- **The installer host stays bare.** `install.sh` is the one step that is not
  signature-checked: whatever that host serves, root runs. Its own subdomain keeps a docs
  compromise away from it. Every install command names `get.vilice.org` and nothing else.
- **The Codeberg repo must be public.** `install.sh` fetches the key with an
  unauthenticated `curl`.
- **The domains are in the trust path**, so the registrar account has two-factor auth,
  transfer lock and auto-renew.
- **Redirect-only hostnames** (`vilice.com`, `www.*`) go to the fixed target
  `https://vilice.org/`, not path-preserving, so no URL on them can resolve to an
  installer. Each carries a proxied record to `192.0.2.1`, which never routes.

## The publish gate

`get.vilice.org` does not go live until the key answers at its Codeberg path, and the
docs do not go live before `get.vilice.org` — the install line must work the moment
someone copies it. `make publish` is that gate as a script.

## How it was built

Full rename, reinstall required, no migration code. Renaming a live account that owns
rootless containers, user units and append-only record files risks a half-finished
migration and a ghost install ([`one-vilice-per-box.md`](one-vilice-per-box.md)).

Left alone on purpose:

- **The `steward` releases up to `0.3.4` are withdrawn**, not kept. Nobody installed
  one, and keeping a version's bytes forever ([`versioning.md`](versioning.md)) protects
  installs.
- **The `steward-app` pack value** in the pinned historical record entry stays; boxes
  holding one must still verify.
- **Past console migrations.** A new migration renames the column, the stored themes and
  the stored ssh users.

## Still to do

1. **The dev box**, reinstalled from `get.vilice.org` on a **new IP**: the old one was in
   the repo's history from the first commit.
2. **Retire the old names.** `steward.agoraforge.org` no longer resolves; its Cloudflare
   project goes, and `codeberg.org/agoraforge/steward` (the old key) is archived.
3. **HSTS preload** for `vilice.org`, once the subdomains settle. It commits every
   subdomain to HTTPS, which is why it waits. (curl ignores the list; the explicit
   `https://` and the signature check cover the install.)
4. **The image names.** The console image is still `ghcr.io/agoraforge/vilice-console`
   (`Makefile`, and the docs examples), and the harness is
   `ghcr.io/agoraforge/harness-rails`, which the App Library points at.
   `ghcr.io/ndhays/…` would put an image where a reader expects it. Decide before the
   first console image is published; after that, a move strands whoever pulled the old
   name.

## Not claimed: package registries

`vilice` is free on RubyGems, crates.io and Homebrew and left unclaimed. Nothing an
install fetches touches a registry, and registries remove placeholder packages as
squatting. Claim it when there is something real to publish
([`open/vilice-mcp.md`](open/vilice-mcp.md)).

## Roads not taken

- **Earlier names.** Hostler, with Switchyard for the console: railway terms that each
  needed a paragraph. Steward said it in one word and collided for that reason.
- **Keep Steward, add a qualifier.** Cannot free a name on `PATH`.
- **VOLIO** (Malvolio minus the "ill"). A live US software-class trademark, five
  companies, npm and PyPI taken. And the play mocks him.
- **A short binary under the brand** (`vil`, `vili`). Two names for one thing. `vil` is
  taken on crates.io and npm and is a typo from `vi`. Anyone can set an alias.
- **tamias** — the Athenian treasurer, publicly audited: the closest fit to Agora.
  Crowded with money software.
- **gastald** — the Lombard royal steward. Free everywhere; the runner-up.
- **klucznik** — the manor's key-keeper. Fits scoped keys; hard to spell, .com taken.
- **benvolio, flavius, reeve, oikos, bryti, epitrop, distain, banto, achates** — taken
  in too many places or hard to say.
- **Horace's own words** — *modus*, *fines*, *aere*. Taken, reads as penalties, and
  unpronounceable, in that order. *Est modus in rebus* would make a fitting motto.
- **famulus** — a servant who obeys. A steward holds bounded authority and answers for
  it.
- **Another word for the account** (`vilicus`). The box would disagree with the product.
- **`sudo vilice …` dropping to the account by itself.** Reverses a deliberate choice in
  [`ceiling-is-the-machine.md`](ceiling-is-the-machine.md): refuse root loudly. A
  separate question.
- **`cli.vilice.org` for the installer.** Names the host after the artifact; `get.` is
  the convention.
- **The source under a company account.** The project is personal.
- **Deploying on push.** For `get.vilice.org` it cannot work — the release needs the
  signing key, which is in no CI — and must not: a push that changes the `install.sh`
  root runs would put GitHub in the trust path. For the docs it is possible and declined:
  that page carries the install line.
- **`vilice.dev` as the home.** HTTPS-only can be had on .org through HSTS preload. Not
  held; cheap to add against a lookalike.
