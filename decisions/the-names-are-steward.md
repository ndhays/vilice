# The names are Steward and Steward Console

> Decided 2026-08-02. **Hostler → `steward`** (the binary, the account, the state dir,
> the record) and **Switchyard → Steward Console** (code identity `console`). Verb packs
> are named `steward-<domain>`.
>
> **Answers** question 8 of [`open/landscape-scan.md`](open/landscape-scan.md) (the
> alternatives list), which is struck from that doc. Question 1 is **re-aimed, not
> answered**: see "What is still open" below.

## The question

Two names, both railway terms: a *hostler* moves locomotives around a yard, a
*switchyard* is where that happens. They pair, and neither says what the thing is
without a paragraph of explanation. The project's own naming rule
([`CLAUDE.md`](../CLAUDE.md), the Orwellian test) says: *if a reader needs the docs to
decode a name, the name failed.* Both failed it, and we kept them because they were
already there.

What forced the question was the layering — core, verb packs, clients (see
[`core-and-packs.md`](core-and-packs.md)). Splitting the deploy verbs out of the trust
core changes what the product *is*: not a deploy tool with unusual auditing, but an
accountable execution layer whose first pack happens to deploy apps. A name chosen for
the errand no longer fits the thing.

## The decision

**`steward`.** A steward acts on an estate on someone else's behalf, under a declared
remit, and keeps the accounts. That is the product, stated in one word a reader already
owns: it acts, its authority is bounded, and it writes down what it did. Plain English,
not a coinage, no classical flourish, short enough to type all day.

Two rules follow, both settled here because both are load-bearing once packs exist:

- **Packs are named by domain, not substrate.** `steward-backup`, never
  `steward-restic`. The pack promises backups happen and are recorded; restic is today's
  implementation. This is the choice already made in the core — it is `deploy`, not
  `podman-flip` — and it is what lets the substrate change without breaking names in
  every `authorized_keys` file and every chain on earth.
- **Verbs stay flat, plain, and forever.** The chain is append-only, so every verb name
  ever invoked is permanent history. `steward deploy` must mean the same thing in 2032.
  The pack is metadata on the entry, not part of the verb — which is why today's
  `backup` and `restore` are *not* re-cut as `backup run` / `backup restore`.

**Steward Console** for the UI. "Switchyard" was the odd one out the moment the metaphor
changed — a railway term in a household one. The code identity is just `console`
(directory `console/`, Rails module `StewardConsole`); "Steward Console" is the product
copy. The console is not privileged and not special: it holds a scoped key and comes
through the door like any other client ([`orchestrators-are-clients.md`](orchestrators-are-clients.md)).

## What it costs

This is a breaking rename, taken at `0.1.5beta` precisely because that is when it is
cheap. A box authorized before it carries `command="hostler _exec …"` in its
`authorized_keys`; the binary that line names is gone, so **the key fails closed**. That
is the correct failure, and it is worth stating plainly: no key silently keeps a
capability under a new name.

**Full on-box rename, reinstall required.** The account, its home, the state dir, and the
record path all become `steward`. There is no in-place migration for `0.1.x`.

## Why no migration path

Renaming a unix account that owns rootless Podman containers, systemd user units, and
`chattr +a` record files is the genuinely painful case — the one where a half-finished
migration leaves a box with a healthy-looking ghost install, exactly the failure
[`one-steward-per-box.md`](one-steward-per-box.md) exists to prevent. Migration code for
that would be written once, carried forever, and exercised for a window measured in
weeks against an install base of roughly one. A documented reinstall is the boring
long-term solution.

## What is deliberately *not* renamed

The Codeberg repo and `switchyard.agoraforge.org`. Both sit inside the installer's chain
of custody: `install.sh` fetches the release public key from the repo and the binary from
the release host, **on purpose from different hosts**, so no single server hands you a
matching key and binary. Moving them is a trust-path change that wants its own decision,
its own commit, and a period where the old locations still serve. It is not a
find-and-replace, and bundling it into a rebrand is how that property gets broken by
accident.

> **Superseded, 2026-08-03. Both moved.** The repo is now
> `https://github.com/ndhays/steward`, and the release/docs host is
> `steward.agoraforge.org`. `install.sh` fetches the key from
> `raw.githubusercontent.com/ndhays/steward` and the binary from
> `steward.agoraforge.org/releases`.
>
> **Why the caution above did not apply: there was no install base.** It argued for a
> transition period so existing installs would not be stranded mid-flight. But nobody has
> ever installed Steward — `0.2.0beta` was never reachable, because the release key lived
> only on a feature branch and the old `main` did not serve it at all. A path no one could
> use is not a path that needs to keep serving. The thing that made this a trust-path
> change rather than a find-and-replace was the *migration*, and there was nothing to
> migrate.
>
> **The property the caution was protecting survives.** The key and the binary still come
> from two different providers — GitHub and `agoraforge.org` — so no single compromised
> server hands you a matching pair. That is what mattered; the specific hostnames never
> did.
>
> Moving both at once also closes the last place the retired name was still load-bearing.
> Keeping `switchyard.agoraforge.org` would have meant every install command a reader
> copies naming a project that no longer exists.

## What is still open

**The collision scan has not been run.** "Steward" is a common English word with real
software precedent, and that is the trade we took knowingly: the naming rule asks for a
word the reader already owns, and words the reader already owns are, by construction,
words other people have used. Question 1 of
[`open/landscape-scan.md`](open/landscape-scan.md) is re-aimed at the new name to find
out how bad it is.

If it comes back badly, the answer is **positioning, not a second rename** — a
qualifier, a tagline, the pack prefix carrying findability. A second rename would break
every `authorized_keys` line again, and by then the chains would carry `steward` verbs,
which are forever.

## Roads not taken

- **Keep Hostler.** It has the virtue of already existing, and it pairs with Switchyard.
  But the pairing is the problem — two obscure terms reinforcing each other is not
  clarity, and every explanation of the name was an explanation the product had to fund.
- **Rename the binary, keep the `hostler` account.** No migration cost, and the box would
  permanently disagree with the product about its own name. The account name appears in
  the forced command, the sudoers grant, the state paths, and every error message that
  says "run it as hostler instead." A rename that stops at the cover is not a rename.
- **Migrate in place.** See above: the cost is permanent, the benefit expires.
- **Rename the console to Manor, Grounds, or Estate.** Committing further to the
  household metaphor buys the same problem the railway metaphor had — a name that needs
  decoding. `Console` says what it is.
