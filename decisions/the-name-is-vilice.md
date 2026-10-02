# The name is Vilice

> Decided 2026-10-01. **Steward → Vilice**, everywhere: the brand, the binary, the
> account (as `_vilice`), the state dir, the record, the env prefix, the packs. **Supersedes** the name
> in [`the-names-are-steward.md`](the-names-are-steward.md); its rules for packs and verbs
> carry over unchanged. **Answers** question 1 of
> [`open/landscape-scan.md`](open/landscape-scan.md), the collision scan.
>
> **Built and published, 2026-10-02.** `0.4.0` is the first Vilice release, installable
> from `get.vilice.org` and verified against the key on Codeberg. What is left is under
> "Building it": the dev box, and retiring the old names.

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
| `github.com/ndhays/vilice` | The source: the main repository. Personal on purpose. **Never in the trust path** — nothing an install fetches comes from GitHub. (`github.com/vilice` is an unrelated, empty account; never link it.) |
| `codeberg.org/vilice/vilice` | The release public key, and only that, at `release-key.pub` in the repo root, fetched from the raw path. |

**Why the source is on GitHub and only the key is on Codeberg.** Codeberg's Terms of Use
now restrict generative-AI code ([`the-core-is-handwritten.md`](the-core-is-handwritten.md)),
and this code is LLM-assisted, so it cannot live there yet. A public key is not code. The
split also adds a property: the key sits on neither the host that serves the binary nor
the one that holds the source, so no one account can change what a release is *and* the
key that vouches for it. A self-hosted mirror of the source may follow; it changes
nothing here.

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

- **The retired `pack` value is not touched** — see below. The `steward` releases up to
  `0.3.4` are withdrawn rather than kept: nobody ever installed one, and keeping a
  version's bytes forever ([`versioning.md`](versioning.md)) protects installs, of which
  there were none. The first Vilice release is **`0.4.0`**: the binary's name is inside
  the tarball, so it could never have been a re-signed `0.3.4` anyway.
- **The `steward-app` pack value** in the pinned historical record entry stays. Boxes
  that hold one must still verify.
- **Past console migrations**, which are history. A new migration renames the column,
  the stored themes, and the stored ssh users.

**Published.** `0.4.0` is signed and served from `get.vilice.org`; the key is at the root
of `codeberg.org/vilice/vilice`; `vilice.org` serves the docs and the App Library. A run
of the live installer with no overrides fetched the key from Codeberg, verified the
release, and installed it. `vilice.com`, `www.vilice.com` and `www.vilice.org` redirect
to `https://vilice.org/` — a fixed target, not path-preserving, so no URL on them can
resolve to an installer. A hostname that only redirects carries a proxied record to
`192.0.2.1`, an address reserved for documentation that never routes.

**Still to do:**

1. **The dev box**, reinstalled from `get.vilice.org` — the first install outside a test.
2. **Retire the old names.** `steward.agoraforge.org` no longer resolves; its Cloudflare
   project goes, and `codeberg.org/agoraforge/steward` (the old key) is archived.
3. **HSTS preload** for `vilice.org`, once the subdomains have settled.

**The gate, for every publish:** `get.vilice.org` does not go live until the key answers
at its Codeberg path, and the docs site does not go live before `get.vilice.org` — the
install line it prints must work the moment someone copies it. An installer pointed at a path that does
not answer fails every install.

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
- **The source under a company account** (`github.com/obelisqueops/vilice`). Considered
  and dropped for `ndhays/vilice`: the project is personal, and the repo should say so.
- **`vilice.dev` as the home.** Its HTTPS-only default can be had on .org through HSTS
  preload, and .org says open source. Not held; cheap to add as a blocker for a
  lookalike install page.
