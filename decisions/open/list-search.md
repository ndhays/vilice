# Steward Console — List Search, Sort & Pagination

> How the Machines list (and, lighter, the Projects grid) becomes searchable,
> sortable, and paged. Planned, not built. Graduates into `blueprint/console/`
> once shipped. Companion to the label system (`../../blueprint/console/data-model.md`)
> and the record-as-spine direction ([ui-roadmap.md](ui-roadmap.md)).

**Last touched:** 2026-06-10.

---

## Why

The compact machine list is built; with labels in place, the fleet wants real
search ("show me `env=prod`"), stable sorting, and paging once it grows past a
screen. Machines get the **robust** treatment (the operator lives here); the
Projects grid gets a lighter version of the same.

## Search

- **One box, server-side.** A single `?q=` filtered in a Rails scope (so it
  composes with sort + pagination and scales). Not client-only.
- **Machines match on:** name, `ssh_host`/`ssh_user`, scope, status, and **labels**.
- **Label selectors (the payoff).** Tokens in `q` that look like `key=value` (or a
  bare `key`) filter by label via the `[key, value]` index; free text does a
  substring match on name/host. v1 = `key=value` exact + bare-key presence + free
  text. Later: `key!=value` negation, `key in (a,b)`, multiple ANDed selectors —
  the same grammar the **Record** forensics view will want.
- **Feel.** Debounced live filtering via a Turbo Frame (the "excellent search"
  feel), degrading to a plain submit. Show a result count and a clear empty state.
- **Model seam.** `Machine.search(q)` returning a relation; label selectors join
  `labels`. Keep the controller thin.

## Sort

- Sortable columns: **name**, **last seen**, **scope**, **status**, **# projects**.
  `?sort=last_seen&dir=desc`; default `name asc`.
- The machine list grows a lightweight **header row** with clickable column
  labels (active column shows the direction) — nudging the list a step more
  "table/file-browser" without losing the compact feel.
- `Machine.sorted(col, dir)` with an allowlist of columns (never interpolate
  user input into ORDER BY).

## Pagination

- Page only past a threshold (a fleet of a few dozen needs none). Page size ~50.
- `?page=`; keep `q`/`sort` in the links.
- **Open:** offset/limit (simple, fine at this scale) vs keyset/cursor (stable
  under churn). Lean offset for v1. **Gem vs hand-rolled:** `pagy` (tiny, fast) vs
  a few lines of `limit/offset` — decide when it's actually needed; no dep until then.

## Projects (lighter)

Same `?q=` box over name + contact + labels; grid stays a grid. Sorting optional
(name / activity). Pagination unlikely to matter near-term.

## Ties / later

- **Focus/pin** (Wave 2): a "Focused" filter is just a pinned predicate over the
  same scope; saved/named searches could follow.
- **Record search** — **BUILT (Wave 2.3):** the `/record` forensics timeline reuses the
  label-selector grammar over actor/action/target (`Event.search`) + a `since` window.
  Since refined: the categorical axes became **dropdowns and pills**, and the grammar
  stayed only so a hand-written or shared link keeps working. Nothing in the UI
  requires knowing it.
- **List search** — **BUILT** for Machines (`Searchable`, the shared label-selector
  parser lifted out of `AppTemplate.search`) and for **Installs** (`Install.search` — free text
  over name / hostname / app / box, no selectors, because installs carry no labels and
  every categorical axis is a grouping chip). Projects is the remaining lighter half.
- **Grouping, not filtering** — **BUILT** and now the primitive both list pages are
  built on (`Groupings`, shared by `MachineGroups`/`InstallGroups`). It answers most of
  what the "sort" section below was reaching for: grouped by the axis that matters,
  with counts, a list rarely needs a sortable column header. **Sort is not built and
  may not be needed** — revisit only if a real fleet asks for it.
- Keep URLs shareable (`q`/`sort`/`page` in the query string) — a filtered fleet
  view is a link you can send.

## Open decisions

- Live Turbo-frame filtering vs submit (lean live).
- Selector grammar depth for v1 (exact `key=value` + bare key + free text).
- Pagination: offset vs keyset; pagy vs hand-rolled; page size.
- Whether the machine list's new header row becomes a full table later.
