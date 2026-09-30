# Steward — Record

What happened, kept honest (invariant 2). Every action writes an accountable entry
**before** it runs.

**Status:** Canonical. Last touched 2026-08-02.

---

## The contract

- **Written before execution.** The entry exists before the action does. A crash in
  the middle still leaves the intent on record.
- **Append-only.** Entries are never edited or deleted, enforced by filesystem
  ownership and the append-only attribute, not by a rule someone could ignore.
- **Hash-chained.** Each entry carries the hash of the one before it, so a silent edit
  or deletion breaks the chain and shows.
- **One writer at a time.** Reading the tail and appending the next entry is a single
  critical section, held under an exclusive `flock` on the record. Two commands at once
  — Steward Console driving the box while an operator types, the ordinary case — would
  otherwise both read seq *N* and both write *N+1*, and because the record is
  append-only that break is **unrepairable without root**. (`record` in `audit.go`;
  the concurrency test is the one that must never regress.)
- **Actor-tagged.** The actor is the authenticated key's client name ([auth.md](auth.md)),
  not a guess from file permissions.

## The entry format

Each entry is one JSON object on its own line (JSONL), appended to
`/var/lib/steward/record.log`:

| Field | Meaning |
|---|---|
| `seq` | 1-based position, contiguous (1, 2, 3 …). A gap is a deletion. |
| `time` | RFC3339, UTC. |
| `actor` | The authenticated key's client name. |
| `scope` | The scope the action ran under (`root` / `operate` / `grant`), or `deny` for a refused attempt. |
| `action` | The command name (e.g. `deploy`, `prepare`). |
| `args` | The recorded arguments — never secret *values* (those ride stdin). Omitted when empty. |
| `digest` | The sha256 of the binary that ran the action. Omitted for the verbs exempt from the binary check (the ceiling, the rights ledger, the record's own reads), and absent from entries written before it was recorded. |
| `pack` | **Retired.** Steward once dispatched to verb packs and wrote the pack's name here; nothing sets it now. Entries on real boxes still carry it, so it is still parsed and still hashed. See [`decisions/roles-not-packs.md`](../../decisions/roles-not-packs.md). |
| `prev_hash` | The previous entry's `hash` (empty for `seq` 1, the genesis). |
| `hash` | This entry's hash (below). |

**The hash** is `sha256` over the canonical JSON of every field *except* `hash` —
`seq`, `time`, `actor`, `scope`, `action`, `args`, `prev_hash`, in that order. An empty
or absent `args` hashes identically to none (the field is `omitempty` on disk, so a
no-arg command must not hash differently from how it reloads). Editing any field,
reordering entries, or dropping one changes a hash and breaks the chain there — which
`steward verify` reports.

**`digest` and `pack` are covered by the hash, and were added additively.** An entry
with neither hashes over exactly the original seven fields, byte for byte; only an
entry that carries one commits to the wider shape (`…, args, pack, digest,
prev_hash`). That is not a nicety — `verify` recomputes every hash, so widening the
payload for all entries would have made every chain already on a box report a break at
entry 1: the record accusing itself of tampering because the software changed.

The retired `pack` field stays in the wider payload for exactly the same reason:
dropping it would accuse every entry that carries one. **Any future field must be
added the same way**, and the pinned hashes in `digest_test.go` are what makes
breaking that rule loud. Being inside the hash is what lets the record attest *which
binary ran*, not merely claim it.

Only state-changing scopes are recorded (`root`, `operate`, `grant`); `observe` reads
(`status`, `logs`, `doctor`, `verify`, `record`, `actors`) do not append — a read
never alters the record it reads.
The format is locked for 1.0 — see [`decisions/record-format.md`](../../decisions/record-format.md).

## One place to get it right

The forced-command path is the single choke point: authenticate → check scope →
**write the entry** → then execute. Because there is no other way in, there is one
place to audit for "is every action recorded first."

## When the record can't be read

If the last line is torn — a crash or a full disk mid-append — every state-changing
command **refuses**, because chaining onto an entry it cannot read would fake the
history. That is the right failure, but refusing without a way out is not: the message
carries the repair (`chattr -a`, drop the partial final line, `chattr +a`, `verify`).
Removing a *whole* entry breaks the chain and `verify` says so — that is the record
working, not a second fault.

## Reads (`observe` scope)

| Command | Does |
|---|---|
| `steward status` | Machine summary, installed apps and their state, the **automatic-maintenance window** (the unattended-upgrades reboot time `harden` set), and any **available package updates** (count, security count, package names). Both are best-effort, unprivileged `apt` reads (absent when apt can't be read). A reader shows the window and offers an "apply now" only when updates are pending. Also **`backups`** — `configured` (is a repo set) and, per target (an app's name, or `machine` for the record snapshot), `last_ok`, `last_failed` and the last failure's `error`, read from `/var/lib/steward/backups.json`, which `backup` writes after each attempt; status never queries the repo. And **`certs`** — per hostname the box serves (its apps' hostnames, plus a balancer's fronted hosts), the certificate a TLS handshake to `127.0.0.1:443` actually gets back: `not_after`, `issuer`, `valid` (chains to a system root and names the host) and `error`. Absent when the box serves no hostname. |
| `steward logs <app>` | Tail an app's logs. |
| `steward verify` | Walk the record and confirm the hash chain is intact — report the first break (reorder, broken link, or edited entry), or that it verifies. |
| `steward record` | Dump the record itself — every entry plus the integrity check — so a reader (Steward Console) can show the witnessed history *and* prove it's unbroken. `verify` answers yes/no; `record` returns the entries. |
| `steward snapshot` | Write one record point — machine and app state at a moment — to the status time-series (`status.jsonl`), kept separate from the audit chain. Not a command a person types: a **systemd timer** (installed by `prepare`) runs it on a cadence, under the actor **`snapshot-timer`** (`STEWARD_ACTOR` in the unit) — without it, a run would be recorded under `operator`, the name a person at the shell gets. |

Residency is **daemonless**: the `snapshot` timer above is installed by `prepare`, so
systemd provides the heartbeat and nothing runs resident on the box.

### The status lane vs. the audit chain

Two append-only stores, kept apart. The **audit chain** (`record.log`) is for *actions*:
hash-chained, actor-tagged, written before an act. The **status lane** is for *state over
time* and is **not** chained — `status.jsonl` (the snapshot time-series) and
`hardening.json` (the latest hardening posture, written by `harden` / `harden --check`)
live here. `hardening.json` is the **privilege bridge**: the hardening check needs root,
but `status` (observe, the unprivileged `steward` user) only ever *reads* the published
fact — the privileged side writes, observe reads, neither crosses the other's boundary.
A reader that finds no `hardening.json` reports "never checked" rather than guessing.

## The record outlives the box

The point of the record is that it survives the thing it records. Reachability bottoms
out at physical or out-of-band access — software never reaches a powered-off box. The
record is what is left when you cannot reach the box, so keeping it honest and keeping
it elsewhere matters more than any live view.

## Open

Open questions for the record are kept out of the spec, in
[`steward-open-questions.md`](../../decisions/open/steward-open-questions.md) — off-host
shipping (so the record survives the box). Tamper-evidence is **settled**: the sha256 hash
chain above, checkable with `steward verify`
([`decisions/record-format.md`](../../decisions/record-format.md)). When the remaining
question settles, its answer moves into this spec and its reasoning into `decisions/`.
