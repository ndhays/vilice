# The name is Vilice

> Decided 2026-10-01. **Steward → Vilice**, everywhere: the brand, the binary, the
> account (as `_vilice`), the state dir, the record, the env prefix, the packs. **Supersedes** the name
> in [`the-names-are-steward.md`](the-names-are-steward.md); its rules for packs and verbs
> carry over unchanged. **Answers** question 1 of
> [`open/landscape-scan.md`](open/landscape-scan.md), the collision scan.
>
> **Built, except the installer and the hosts.** The code, the console, the site and the
> docs say Vilice. `install.sh`, the site's URLs and the repo links still name
> `steward.agoraforge.org` and `agoraforge/steward`, behind the gate under "Building it".

## The question

"Steward" collides. It is a common English word, which is why it was chosen, and
common words are by construction words other people have used. Other tools already
claim it in the CLI namespace, the one place a collision is not cosmetic: a name on
`PATH`, a unix account, a directory under `/var/lib` can each be held by only one thing
per box.

The Steward decision saw this coming and said: if the name comes back muddied, the
answer is positioning, not a second rename, because "the chains would already carry
`steward` verbs, and verbs are forever." That reason does not hold up:

- **The record carries verbs, not the binary name.** The verbs are flat — `deploy`,
  `backup`, `rollback` — and survive a rename untouched. The name lives in the
  `authorized_keys` forced command, the account, the paths and the env vars: things
  tied to an install, not to history.
- **There is still no install base.** One dev box, at `0.3.4`. That is the same reason
  the Hostler rename was cheap, and it gets dearer with every release.

So a tagline can fix findability, but it cannot free a name on `PATH` or a unix account.
Only a rename can, and now is the cheapest it will ever be.

## The decision

**`vilice`.** In *Epistles* 1.14 Horace writes a letter to the steward who runs his
Sabine farm. It opens *"Vilice silvarum et mihi me reddentis agelli"* — "Steward of the
woods and the little farm that gives me back to myself." *Vilice* is the form of address
of *vilicus*, the Roman estate steward: he ran the land on the owner's behalf, under a
set remit, and answered for it. That is the product: it acts, its authority is bounded,
and it writes down what it did. The meaning Steward carried survives as the story.

One name, everywhere:

| Where | Was | Becomes |
|---|---|---|
| Brand, product copy | Steward | Vilice |
| Binary, forced command | `steward` | `vilice` |
| Unix account | `steward` | `_vilice` |
| State dir, record | `/var/lib/steward` | `/var/lib/vilice` |
| Env vars | `STEWARD_*` | `VILICE_*` |
| Packs | `steward-<domain>` | `vilice-<domain>` |
| Console product copy | Steward Console | Vilice Console |
| Console Rails module | `StewardConsole` | `ViliceConsole` (directory stays `console/`) |

**The account is `_vilice`.** It is still the product's name — the box does not
disagree with itself, the failure the Steward decision rejected in "rename the binary,
keep the account" — and the underscore marks it as a service account, not a person or a
command: the convention OpenBSD and macOS use for every daemon (`_sshd`, `_www`) and newer
Debian system accounts follow (`_apt`, `_chrony`). So `sudo -u _vilice vilice` reads as
"as the vilice service account, run vilice", where `sudo -u steward steward` read as a
typo. Directories take no prefix.

The Steward rules carry over as they stand: packs are named by domain, not substrate
(`vilice-backup`, never `vilice-restic`); verbs stay flat, plain, and forever.

## Why a coined word passes, here

This breaks the naming rule in [`CLAUDE.md`](../CLAUDE.md) on purpose: a reader will
not decode "vilice" without being told. The rule asks for a word the reader already
owns, and a word the reader already owns is a word somebody else already uses. For the
name of the product itself — the one name that has to be unique on every box — owning
it outright beats having it explain itself:

- **It is free where a clash bites.** No binary on `PATH`, no account, no package in
  apt, Debian or AUR (scan below).
- **It is one string.** An agent reading "steward" in a log, a prompt or a search
  result has to work out which steward is meant. "vilice" means one thing. As more of
  the commands are written by agents rather than typed, being unique matters more than
  being easy to say.
- **The story does the explaining.** One sentence — Horace's letter to his farm
  steward — tells a reader what the thing is for.

The rule still holds for everything below the product name: verbs, packs, models,
methods, files. They stay plain words.

## The collision scan, 2026-10-01

- **On the box:** no `vilice` binary, account or group; no package in apt, Debian or AUR.
- **Registries:** free on crates.io, npm, PyPI, RubyGems, Homebrew (formula and cask),
  the Go module proxy, Docker Hub and Codeberg.
- **GitHub:** the user `vilice` is an empty account from 2021, so `github.com/vilice`
  is not ours. The repo lives on Codeberg, so this does not matter.
- **Companies and products:** none found by that name.
- **Trademark:** no exact VILICE mark found; the nearest US marks are near-misses
  (VILICO, VILICERT, VILI). Not a legal opinion; worth a lawyer's look before any
  commercial use.

## Domains

| Host | Serves |
|---|---|
| `vilice.org` | The site and docs. The project's home: .org for the open-source project. |
| `get.vilice.org` | `install.sh` and the release binaries. Nothing else. |
| `vilice.com` | Redirects to `vilice.org` for now; held for a business site later. **Never serves `install.sh`.** |
| `codeberg.org/vilice/vilice` | The release public key, from the repo's raw path. |

**The installer host stays bare.** `install.sh` is the one step in the install path that
is not signature-checked: whatever that host serves, root runs. Keeping it on its own
subdomain means a site or docs compromise does not reach it. Every install command in the
docs, README and site names `get.vilice.org` and nothing else, so there is one address to
paste.

**The key stays on a second provider.** The binary comes from `get.vilice.org`, the key
from Codeberg — two providers, as before, so no one server can hand you a matching key
and binary. The Codeberg repo must be publicly readable (see the superseded note in
[`the-names-are-steward.md`](the-names-are-steward.md)): `install.sh` fetches the key
with an unauthenticated `curl`.

**The domains are in the trust path**, so the registrar account has two-factor auth,
transfer lock and auto-renew. Once the subdomains are settled, `vilice.org` goes on the
HSTS preload list. That protects the page the install command is copied from (curl
ignores the list; the command's explicit `https://` and the signature check cover the
install itself). It commits every subdomain to HTTPS, which is why it waits.

## Building it

Full rename, reinstall required — no migration code, for the reason given in
[`the-names-are-steward.md`](the-names-are-steward.md): renaming a live account that owns
rootless Podman containers, user units and append-only record files is the painful case,
and the install base is one dev box. That box is reinstalled, and its record and key go
with it.

What does not move, on purpose:

- **The signed releases up to `0.3.4`** keep their `steward` names. A version is one set
  of bytes forever ([`versioning.md`](versioning.md)), and the binary's name is inside the
  tarball, so the first Vilice binary ships as a new version. Until it does, the site's
  release guard refuses to build — correctly.
- **The retired `pack` value `steward-app`** in the pinned historical record entry. Boxes
  that hold one must still verify.
- **Past console migrations**, which are history. A new migration renames the column,
  the stored themes, and the stored ssh users.

What is left, in order: register `get.vilice.org` and the Codeberg `vilice` org; cut the
first Vilice release; point `install.sh`, the site's URLs and the repo links at the new
hosts; reinstall the dev box.

**The gate:** `install.sh` does not change until `get.vilice.org` serves the release and
`codeberg.org/vilice/vilice` serves the key. Point the installer at a path that does not
answer and every install fails its check.

## Roads not taken

- **Keep Steward and add a qualifier.** Fixes findability, not the clash: a tagline
  cannot free a name on `PATH` or a unix account.
- **VOLIO** — Malvolio, the steward in *Twelfth Night*, minus the "ill". Short and easy
  to say, but a live US trademark in the software class (O.C. Tanner, headphones and
  device accessories), five companies by the name, npm and PyPI taken, .com parked. And
  Malvolio is the steward the play mocks.
- **A short binary under the brand** (`vil`, `vili`, `vilit`). Two names for one thing,
  and the box disagreeing with the product about its own name — the split the Steward
  decision already rejected. If agents do the typing, six letters cost nothing. `vil` is
  taken on crates.io and npm and sits a typo from `vi`. Anyone who wants a short name can
  set an alias; that choice stays theirs, not baked into every `authorized_keys`.
- **tamias** — the Athenian treasurer, publicly audited at the end of office: the
  closest fit to Agora. But the name is crowded with money software (a POS system, an
  expense app, a portfolio tracker, an invoicing tool) and .com is taken.
- **gastald** — the Lombard steward of the king's estates. Free everywhere; the
  runner-up if vilice ever runs into trouble.
- **klucznik** — Polish for the manor's key-keeper. Fits scoped keys exactly, but
  crates.io and .com are taken and the spelling is hard.
- **benvolio**, **flavius**, **reeve**, **oikos**, **bryti**, **epitrop**, **distain**,
  **banto**, **achates** — each either taken in too many places or hard to say for no
  better story.
- **Horace's lines as the name** — *modus* and *fines* ("est modus in rebus, sunt certi
  denique fines"), *aere* ("exegi monumentum aere perennius"). *modus* is taken
  everywhere; *fines* reads as penalties; *aere* has no obvious sound. The first line
  would make a fitting motto: bounded scope is the whole design.
- **famulus** — a servant who obeys. A steward holds bounded authority and answers for
  it; that difference is the product.
- **Another word for the account** (`vilicus`, say). Fixes the `sudo -u x x` stutter
  by making the box disagree with the product about its own name again.
- **`sudo vilice …` dropping to the account by itself**, instead of refusing root. Ends
  the `sudo -u` entirely, but reverses a deliberate choice in
  [`ceiling-is-the-machine.md`](ceiling-is-the-machine.md): refuse root loudly; a
  privileged process never quietly becomes something else. A separate question, not
  part of a rename.
- **`cli.vilice.org` for the installer.** Names the host after the artifact, not the
  job. The host hands out releases, which may later be more than the CLI. `get.` is
  also the familiar convention.
- **`vilice.dev` as the home.** Its HTTPS-only default can be had on .org through HSTS
  preload, and .org says open source. Not held; cheap to add as a blocker for a
  lookalike install page.
