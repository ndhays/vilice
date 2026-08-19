# Steward Console — UI Build Roadmap

> The shape is **settled and graduated**: the canonical interface is in
> [`blueprint/console/interface.md`](../../blueprint/console/interface.md), and the
> *why* (Shape B over the rejected admin-panel and command-surface shapes) is in
> [`decisions/ui-shape.md`](../ui-shape.md). What remains here is the **build roadmap** —
> what's done, what's next — plus a handful of still-open sub-questions.

**Last touched:** 2026-06-16.

---

## Build roadmap — four waves of five

Ordered by dependency. Built items are one line; open items keep their detail.

### Wave 1 — Foundations + first live round trip
1. **Theme/skin system** — BUILT.
2. **Icon system** (lucide) — BUILT.
3. **Live observe round trip** (`MachineStatus`, health line, cached scoped-SSH read) — BUILT.
4. **"You are here" recognition** (`machine_id` in `steward status`, matched to
   `STEWARD_SELF_MACHINE_ID`) — BUILT.
5. **Drop Dispatcher** — BUILT (nav is one-lens; concept retired, see
   [`decisions/ui-shape.md`](../ui-shape.md)).

### Wave 2 — The record as spine (observe side)
6. **Ingestion** — *open.* The read+merge half is built (`steward record` verb, the
   two-record merge, the chain-integrity line). **Still open:** the *persistent* mirror +
   Steward Console's own-record schema (whether `Event` becomes Boxcar `Eventable` and persists
   box entries for cross-fleet query — the Boxcar audit), **dedup** of a Steward Console-issued
   box command appearing as both its own `Event` and a box entry, and `Snapshot` ingestion
   cadence (on-demand vs. background job). This blocks the fleet-wide Record/Now and the
   state-driven machine-row name cell. See
   [`console-open-questions.md`](console-open-questions.md) and
   [`../two-records.md`](../two-records.md).
7. **Unified entity page pattern** (header + head + chain-as-body) — BUILT.
8. **The Record destination** (`/record`, filter by actor/action/target/time;
   `Event.search` selector grammar + `since`; shareable URL) — BUILT (Wave 2.3).
9. **Now / fleet pulse** (calm, exceptions rise) — BUILT (Wave 2.3). The "live head of
   the chain" half was built and then **removed**: Status is an inbox, not a feed —
   what needs you, or *Nothing to report*. See
   [`../status-is-an-inbox.md`](../status-is-an-inbox.md).
10. **Focus/pin lens** — *open.* Only `Project` carries `starred` today (plus the this-box
    self-pin); Machine/Install need the same generic pin, then a "Focused" predicate over
    `Event.search`. Global pins for now; per-user when delegation (Access) lands.

### Wave 3 — The mutate ceremony (write side)
11. **Mutate ceremony component** — BUILT (Wave 3.1; outcome model in
    [`../record-outcome-on-the-entry.md`](../record-outcome-on-the-entry.md)).
12. **Deploy / rollback through the ceremony** — BUILT for existing apps (Wave 3.2; compose
    step pins a digest, envelope on scoped-SSH stdin). *Still ahead:* **first-deploy via UI**
    (new app/target) and env/secret/volume compose (#14).
13. **Lifecycle acts** (apply-updates, start/stop/restart, remove) — BUILT (Wave 3.1+3.3).
14. **Secret & env UI** — *open.* The **declaration** half is built (`App.env` as
    `{ key, secret }`, `App.secret_files`). **Still open — the value half (#14-B):** the
    install/redeploy form collects values (env recorded; secret + file values off-record on
    stdin) and `Install#deploy_envelope` carries `secrets`/`secret_files`/`secret_values`.
    Direction: **secret-by-default**, one Environment panel, two visibly-distinct modes
    mapping 1:1 to Steward's two delivery channels. See
    [`console-open-questions.md`](console-open-questions.md) and
    [`app-library.md`](app-library.md).
15. **Live-watch transport** — *open.* Stream an act's sub-steps from Steward (held
    connection vs. poll) so the ceremony's settle step is live, not blocking. Needs a
    Steward sub-step protocol — Steward returns one final JSON result today, so this is a
    **Steward-side contract change**, planned before built. Ties to the standing-connection
    question.

### Wave 4 — Trust, access, the client lens
16. **Access / rights ledger** — **BUILT** (the read half). `/access` lists every box's
    grants — actor, scope, key type, OpenSSH fingerprint — read live through the new
    `steward actors` verb rather than from anything stored, and leads with keys Steward
    did not write. Building it surfaced that the box had no way to *read* its own
    ledger: `authorize`/`revoke` wrote `authorized_keys` and nothing reported it, so the
    verb had to come first ([`blueprint/steward/auth.md`](../../blueprint/steward/auth.md)).

    Since rebuilt as **one grouped list, not a card per box** — grouped by *reach*
    (an ungated key has no ceiling, so it sits above `grant` on one ladder), by *box*,
    or by *actor*, which answers "where does this actor reach" — a question the card
    layout could not answer at all. Graduated to
    [`blueprint/console/interface.md`](../../blueprint/console/interface.md).

    *Still open:* **authorize/revoke as a ceremony** from this page. It is a mutate, so
    it belongs in the mutate component (#11) with the record-before-act confirm, and it
    needs the grant-scoped key the console does not hold today — the console reads with
    `observe`. Also open: a per-machine Access panel, versus the fleet roll-up built here.
17. **Chain-integrity badge** — *open.* Verify + surface `✓ record intact · N entries ·
    unbroken since prepare` (the machine page already shows per-box integrity; this is the
    fleet-level trust signal).
18. **Shareable observe view** — *open.* The Project page, observe-only, as the client
    status page (enforces the no-leak isolation rule —
    [`journeys.md`](../../blueprint/console/journeys.md)).
19. **Command palette** — *open.* Nav + observe queries only; off the mutate path.
20. **Steward Console-deploys-Steward Console** — *open.* Localhost as a `Machine` row, self-deploy
    with the OOM-sensitive caveat surfaced. The proof. See
    [`console-open-questions.md`](console-open-questions.md).

### Beyond #1–20 — the install front-of-funnel
Built and now graduated into [`blueprint/console/journeys.md`](../../blueprint/console/journeys.md):
the App Library catalog + install-from-project + library-only setting + custom images
([`app-library.md`](app-library.md)), Add Project / Add Machine onboarding
([`machine-onboarding.md`](create-machine.md)), the Install-as-app-actions-home
([`../install-the-app-actions-home.md`](../install-the-app-actions-home.md)), and
attach-existing-machine. *Still ahead here:* **detach** a machine from a project (needs
row-context UI), and the **migrate/re-target** verb (move an install to another box) — see
[`console-open-questions.md`](console-open-questions.md).

Graduated 2026-08-19, all canonical in the blueprints now:

- **The form pattern** — `machines/new` is the reference shape and `installs/new` follows
  it ([`interface.md`](../../blueprint/console/interface.md)). Pinned in tests, because a
  vocabulary nothing checks drifts apart again.
- **An install needs no box.** It is an intention; the gap it opens is a first-class
  state, and creating and placing are two acts
  ([`journeys.md`](../../blueprint/console/journeys.md)).
- **Whether a gap is closable** — `candidate_machines` / `ready_machines`, surfaced on the
  install and called out once on Status
  ([`data-model.md`](../../blueprint/console/data-model.md)).
- **Logs** — `steward logs` read on request, uncached, offered even where the key cannot
  act.
- **Look up digest** ([`a-tag-is-not-a-release.md`](../a-tag-is-not-a-release.md)) and the
  **release command** ([`release-command.md`](release-command.md), still open in parts).
- **One glyph, one meaning** across nouns, and the vertical rhythm named on the canonical
  space scale ([`tokens.md`](../../blueprint/design/tokens.md)).

---

## Still-open sub-questions

- **Machine-row name cell** — the protagonist of a machine row should be the box's reported
  name + reachability (three states: *not yet seen* `—` → live name → last-known, **stale**).
  Blocked on #6: the fleet list does no per-machine live read, so the reported hostname is
  live-SSH only, not persisted. Persisting `reported_hostname` + `last_seen` *is* ingestion;
  fold this in there.
- **Live-watch transport** (#15): held SSH connection vs. poll.
- **Status transitions in the timeline** — the second half of the interleave rule. The
  first half is settled and enforced: a routine sample is not an act and never enters a
  chain (`Event.acts` + `ChainItem#status?`, graduated to
  [`../../blueprint/console/interface.md`](../../blueprint/console/interface.md), why in
  [`../a-sample-is-not-an-act.md`](../a-sample-is-not-an-act.md)). Surfacing real
  transitions — "went critical 03:12", "recovered 03:40" — is **blocked on #6**:
  `Snapshot` is declared but nothing writes it, so there is no series to derive one from.
- **Command-palette scope**: nav + observe only (current call) vs. compose-mutate later.
- **Pin scope**: global now; per-user when Access lands.
- **Token name convergence** — the console's palette now matches
  [`../../blueprint/design/tokens.md`](../../blueprint/design/tokens.md) by *value*, but
  still says `--bg`/`--muted` where the canonical document says `--paper`/`--ink-soft`.
  The rename is a mechanical sweep across the seven console stylesheets; it was held back
  from the theme change so that one was a palette change and nothing else. Until it lands
  the mapping table in that document is the bridge.
- **Operator-defined themes** — `Theme::ALL` plus a pair of `tokens.css` blocks is the
  whole contract, so a user-supplied theme is a matter of storing token values rather than
  restructuring anything. Open: where they live (a row per theme vs. a blob on the user),
  and whether a custom theme may set the rail colours or only the palette.
- **List mechanics** (search / sort / pagination, label-aware) — the plan is in
  [`list-search.md`](list-search.md).
- **Board view** is a later *skin* over the state-forward list — machines as lanes, installs
  as state-coloured cards, drag to place — a render of the same query, not new plumbing.
  Build the state-forward list first.
