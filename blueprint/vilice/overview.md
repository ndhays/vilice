# Vilice

> The entry point for the Vilice spec. Plain prose here; the per-concern files
> next to it carry the detail.

**Status:** Canonical. Last touched 2026-08-02.

---

## What it is

Vilice is the program on every machine. It is the layer with the privilege: it runs
apps as containers, routes traffic to them, and keeps the record of what happened. A
single static Go binary, run as **the one `_vilice` user** — one account per box, one
state dir, one record, and the binary refuses to act as anyone else (see
[`decisions/one-vilice-per-box.md`](../../decisions/one-vilice-per-box.md)).

You reach it over **scoped SSH** — a key pinned to a forced command. Day to day a
person doesn't type it; Vilice Console drives it over that same channel. It is also the
breakglass tool: the operator always has it over their own SSH.

## The one claim

Everything Vilice does rests on a single property:

> **Un-bypassability** — there is no path to the box's power that skips a named,
> scoped, recorded invocation.

That is the whole security claim, and it is small enough for one person to check.
Vilice is where the Agora articles stop being words and become mechanism.

The claim holds **without an asterisk**, and the mechanism is that **no scope is a
shell**: every key resolves to a named command or to nothing, so there is no grant whose
holder can act on the box without an entry being written first. The top rung used to hand
out an interactive shell, and that one exception is what the claim used to be missing —
see [`no-key-gets-a-shell.md`](../../decisions/no-key-gets-a-shell.md).

## Tenets

What Vilice is, one line each — with the mechanism that makes the line true, per the
Agora rule that an article without a mechanism isn't applied:

- **One door.** A single entry for hosting apps on a Linux box. The door is also the
  audit point — one door is *why* un-bypassability is checkable at all.
- **Plain speech.** It talks like a person, not a manual — admin-level precision in
  non-admin vocabulary. Mechanism: every command carries its own help page, and every
  usage error carries the synopsis (they are the same string in `internal/core/dispatch.go`, so they
  can't drift).
- **Standard tools, standard idiom.** It relies on Podman, Caddy, OpenSSH, and systemd
  *on purpose* ([`decisions/borrowed-substrate.md`](../../decisions/borrowed-substrate.md))
  and drives them in their native config — never a fork, never a private format.
  Everything it writes is the tool's own plain file, readable by an admin who has
  never heard of Vilice.
- **A gate and a scribe, not a runtime.** No daemon, no listener, no token; it exists
  only while a command runs. Delete the binary and nothing running stops — apps are
  ordinary Quadlet units under systemd, routes are plain Caddy config. What stops is
  the gate and the record.
- **One vilice per box.** One named account, one state dir, one record — enforced by
  the binary, not the README
  ([`decisions/one-vilice-per-box.md`](../../decisions/one-vilice-per-box.md)).
- **If it can't write the record, it doesn't act.** `dispatch` writes the entry before
  the action runs (invariant 2, in `internal/core/dispatch.go`).
- **Fail loud, never silent.** An unknown flag is refused, the wrong user is refused,
  a failed pull is classified — a quiet wrong outcome is worse than a loud stop.
- **Breakglass is the tool itself.** Recovery is Vilice over the operator's own SSH,
  never the web UI.
- **Open.** AGPL, auditable, one person can hold it in their head
  ([`decisions/licensing.md`](../../decisions/licensing.md)).

## The core and the app layer

Vilice is two layers in one binary. The **core** (`internal/core/`) owns the gate,
the record, and the ceiling; the **app layer** (`internal/app/`) owns what a verb
actually does. The core resolves a name, applies the account gate, writes the record,
and calls the function — it never learns what the function does. Where the ceiling has
to *tell* an operator about the substrate — what `uninstall` leaves on the box — it asks
the layer rather than reciting a list of its own: the layer installed it and knows what
this box's role got.

The line is a Go interface, `core.Apps`, with exactly one implementation, wired in at
compile time by `cmd/vilice`. Nothing is discovered and nothing is loaded: this is
organisation, written down where the compiler can hold us to it, not a plugin system.
Vilice once had one of those; the far side of the seam stayed permanently empty and
it was dropped
([`decisions/roles-not-packs.md`](../../decisions/roles-not-packs.md)).

What must be trusted is therefore **the binary**, and the claim that this is
auditable rests on it being handwritten rather than on a smaller boundary inside it
([`decisions/the-core-is-handwritten.md`](../../decisions/the-core-is-handwritten.md)).
What the binary *is* is checkable: `prepare` records its sha256 at
`/etc/vilice/binary.digest`, and every verb that acts compares the running
executable against that line before it runs.

## The four concerns

Each is one spec, and each is one surface to audit on its own:

- **[provision.md](provision.md)** — get the box ready (`harden`, `prepare`). Lays
  the floor the rest stands on. Core.
- **[auth.md](auth.md)** — who may act, at what scope (scoped SSH). Invariant 1. Core.
- **[record.md](record.md)** — what happened, kept honest. Invariant 2. Core.
- **[deploy.md](deploy.md)** — put apps on the box and run their lifecycle. Wide,
  not deep. This one is the **app layer**, not core.

## The legible ceiling

Three commands are **root-only** and reachable by no scoped key: `harden`, `prepare`,
and `uninstall`. They change the box itself, so a scoped key must never reach them —
the gate cannot rebuild (or remove) its own gate. This is invariant 3, enforced by filesystem ownership. Every other
command, including `authorize`/`revoke`, runs as the unprivileged `_vilice` user:
granting and revoking are the **top rung of the scope ladder** (`grant` scope), not a root
wall above it — the ceiling is the machine and the record, not the rights ledger. Named
in [provision.md](provision.md) and [auth.md](auth.md); the why is in
[`decisions/ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).

## Command reference

**There is one description of the CLI, and it is the CLI.** `core.Commands` — the
table in `dispatch.go` plus what the app layer contributes — carries every verb's
summary, paragraph, synopsis, flags (each with its own description), and examples.
Everything else is a view of it:

| View | How |
|---|---|
| `vilice help <command>`, `--help` | `commandHelp` renders the page |
| A `bad_args` error | The same synopsis string, appended |
| `vilice(1)` | `vilice _man` → `make man`, shipped in the release tarball |
| The documentation site | `vilice _commands` → JSON, printed **verbatim** at the top of each page under `/commands/` |

The specs in this folder say how each command *behaves* and which article it
encodes. What it is called, what it takes, and how it is typed is the table's job,
and is not restated here or on the site. See
[`decisions/help-is-the-documentation.md`](../../decisions/help-is-the-documentation.md).

Three properties are mechanism rather than habit, enforced by `core.CheckDocs` and
tested against the assembled binary in `cmd/vilice`:

- **A flag cannot exist undocumented.** The `Flags` list is both what the gate
  admits (`unknownFlag`) and what help prints — one list, so a flag the reader is
  told to type is a flag the gate accepts, and neither can be added without the other.
- **Help is scoped.** Every page states which scope may run the command and whether
  the invocation is recorded before it runs, making help a second view of the rights
  ladder and of invariant 2.
- **Help fits.** Pages are capped at `core.HelpWidth` (78 columns) — the terminal
  nobody widens, and the width the site's fixed-width block was sized from.

A flag a command doesn't declare is a hard error carrying the synopsis, never
silently dropped; `--help` never falls through to the action it asks about.

## The reply — what a caller can rely on

Every verb answers the same way, so a console, a script or an agent never scrapes text.

- **`--json` puts one document on stdout and nothing else**: the `Result` —
  `code` (`ok`, or a named failure), `retryable`, `message`, and `data` for reads.
- **Everything else is on stderr.** A verb drives other tools — apt, Podman, Caddy,
  systemctl — and what they print while they work is the log, not the reply. For the
  length of the run the binary's stdout *is* its stderr (`runQuietly`), so no tool can
  put a line in front of the JSON. A caller reads the two streams apart. Without
  `--json`, a person is watching and the tools print where they always did.
- **The exit status is `0`, `1` or `2`**: done, failed (the `code` says how, and
  `retryable` says whether to try again), or called wrong. Over scoped SSH a `255` is
  ssh's own and means the box was never reached.

## Open questions

What is not yet decided is kept out of this folder, in
[`decisions/open/vilice-open-questions.md`](../../decisions/open/vilice-open-questions.md).
When a question settles, its answer moves into the spec here and its reasoning into
`decisions/`.
