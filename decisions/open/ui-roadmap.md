# Vilice Console — UI Build Roadmap

> The shape is **settled**: the canonical interface is in
> [`blueprint/console/interface.md`](../../blueprint/console/interface.md), and the *why*
> (Shape B over the rejected admin-panel and command-surface shapes) is in
> [`decisions/ui-shape.md`](../ui-shape.md). What remains here is **what is still open** —
> built work is in the blueprint, and its history is in the commits. Item numbers are kept
> because code and other docs cite them.

---

## Open, by number

6. **Ingestion.** The read+merge half is built (`vilice record`, the two-record merge,
   the chain-integrity line). **Open:** the *persistent* mirror and Vilice Console's
   own-record schema (whether `Event` becomes Boxcar `Eventable` and persists box entries
   for cross-fleet query), **dedup** in a persisted mirror (the machine page already shows
   a console-issued act once, matched at display time by `Chain.for_machine`), and
   `Snapshot` cadence (on demand vs. a background job). This blocks the fleet-wide Record,
   the state-driven machine-row name cell, and the Machines board. See
   [`console-open-questions.md`](console-open-questions.md) and
   [`../two-records.md`](../two-records.md).
10. **Focus/pin lens.** Only `Project` carries `starred` today (plus the this-box
    self-pin); Machine and App need the same generic pin, then a "Focused" predicate over
    `Event.search`. Global pins for now; per-user when delegation (Access) lands.
12. **First deploy of a brand-new app through the UI.** Deploy and rollback of existing
    apps go through the ceremony. The Apps flow's first deploy still goes add → place →
    ceremony; whether a template can go straight to a running app in one screen is open.
14. **Secret & env — the remainder.** Declaration and values are built (values encrypted
    at rest, supplied on the app's own page, resent off-record on every deploy). **Open:**
    per-version overrides, and the dropped `default` / `required?` fields — see
    [`app-library.md`](app-library.md).
15. **Live-watch transport.** Stream an act's sub-steps from Vilice (held connection vs.
    poll) so the ceremony's settle step is live, not blocking. Vilice returns one final
    JSON result today, so this is a **Vilice-side contract change**, planned before built.
16. **Access — the write half.** The read half is built (`/access`, one grouped list). The
    console revoking **its own** key on Remove is built, for a grant-scope key
    ([`machine-settings-is-a-page.md`](../machine-settings-is-a-page.md)). **Open:**
    authorizing and revoking *other* actors from this page, as a ceremony with the
    record-before-act confirm, and the grant-scoped key that needs; and a per-machine
    Access panel versus the fleet roll-up.
17. **Chain-integrity badge.** Verify and surface `✓ record intact · N entries · unbroken
    since prepare` fleet-wide (the machine page already shows it per box).
18. **Shareable observe view.** The Project page, observe-only, as the client status page
    (enforces the no-leak isolation rule — [`journeys.md`](../../blueprint/console/journeys.md)).
19. **Command palette.** Nav + observe queries only; off the mutate path.
20. **Vilice Console deploys Vilice Console.** Localhost as a `Machine` row, self-deploy
    with the OOM-sensitive caveat surfaced. The proof. See
    [`console-open-questions.md`](console-open-questions.md).

## Open — the overhaul

What the console is for is settled in
[`../what-the-console-is-for.md`](../what-the-console-is-for.md), and every entity page
takes the zones shape in the blueprint. Still open, in order:

- **The app page in zones.** What it is = the spec, interpreted (image, hostnames, env
  names, volumes; accessories and processes nested under the app), with the literal deploy
  envelope behind a *Raw spec* disclosure (secret names only). Observe = where it runs,
  running vs. asked for. Operate = the command buttons, per box.
- **What a command does on the box.** Belongs in the record entry, not on the page: what
  apply-updates ran (its two apt commands) and how to check it. Read from
  `vilice _commands`; where that lacks the detail it grows in the binary, not the console.
  Open: how the console gets the table — `_commands` is not reachable through `_exec`, so
  either a build-time copy (as the docs site does) or a new observe verb.
- **Machines list as the board.** Status stays the inbox; the Machines list becomes the
  glanceable board — every box's memory, disk and reachability at once. Blocked on
  ingestion (#6).
- **An act in flight** — *a bug today.* Confirm blocks the request until the SSH call
  returns, with nothing on screen saying it is running. Wants a running state in the
  ceremony (the entry already exists as *pending*) and, later, streamed output (#15).
- **Visual pass.** Card alignment and density, after the above.
- **Detach** a machine from a project (needs row-context UI), and the **migrate /
  re-target** verb (move an app to another box) — see
  [`console-open-questions.md`](console-open-questions.md).

## Still-open sub-questions

- **Machine-row name cell** — the protagonist of a machine row should be the box's
  reported name + reachability (three states: *not yet seen* `—` → live name →
  last-known, **stale**). Persisting `reported_hostname` + `last_seen` *is* ingestion;
  fold this into #6.
- **Status transitions in the timeline** — "went critical 03:12", "recovered 03:40". A
  routine sample never enters a chain ([`../a-sample-is-not-an-act.md`](../a-sample-is-not-an-act.md));
  real transitions are blocked on #6: `Snapshot` is declared but nothing writes it, so
  there is no series to derive one from.
- **Command-palette scope**: nav + observe only (current call) vs. compose-mutate later.
- **Pin scope**: global now; per-user when Access lands.
- **Token name convergence** — the console's palette matches
  [`../../blueprint/design/tokens.md`](../../blueprint/design/tokens.md) by *value*, but
  still says `--bg`/`--muted` where the canonical document says `--paper`/`--ink-soft`. A
  mechanical sweep across the console stylesheets; until it lands, the mapping table in
  that document is the bridge.
- **Operator-defined themes** — `Theme::ALL` plus a pair of `tokens.css` blocks is the
  whole contract, so a user-supplied theme is a matter of storing token values. Open:
  where they live (a row per theme vs. a blob on the user), and whether a custom theme may
  set the rail colours or only the palette.
- **List mechanics** (search / sort / pagination, label-aware) — the plan is in
  [`list-search.md`](list-search.md).
- **Board view** — a later *skin* over the state-forward list: machines as lanes, apps as
  state-coloured cards, drag to place. Build the state-forward list first.
