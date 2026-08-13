# Steward Console — Interface

> How Steward Console looks and behaves: the record is the spine, observe and mutate are
> kept apart, and every screen is a lens on the one record. The *why* — and the shapes
> rejected — is in [`decisions/ui-shape.md`](../../decisions/ui-shape.md).

**Status:** Canonical (the shape is settled and largely built — Waves 1–3). The build
roadmap and the screens still ahead live in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). Last touched 2026-08-12.

---

## What it calls itself

**"Steward Console" is the Rails app's name, not a product name.** The UI says
**Steward** and nothing else: one product, one name, the same one you type at a
shell. The chrome wears the canonical wordmark from
[`blueprint/design/logo.md`](../design/logo.md) — the mark, then `steward` in mono,
lowercase — in the rail and on the sign-in card alike. Prose that has to name this
surface calls it *the console*, lowercase, the way you'd say *the CLI*.

---

## The shape: the record is the spine

The protagonist of the UI is the **record** — what happened, who did it, what it touched
— not the current state. Current state is just *the head of the record*. This is the one
thing no server-admin panel copies, because they don't keep the chain. Everything below
follows from that choice.

### The design law: a view shows what it's FOR

Every screen surfaces **what it's for** — the answer, the most relevant state — not the
inputs you typed to make it. One level down from "the record is the protagonist." It is
what justifies showing a machine row's address as plain truth (the SSH user is always
`steward`, so `steward@host:22` is noise — drop it) and showing the box's reported name
plainly rather than guarding it with a match/mismatch check (the SSH connection is already
verified; a wrong box surfaces on its own).

## The spine in two halves: observe vs mutate

Everything Steward Console does is one of two things, kept apart on purpose — Steward's scope
ladder surfaced in both the UI and the architecture (see
[`overview.md`](overview.md) and `app/services/steward.rb`):

- **Observe** — read the record Steward ships. Zero-privilege: holds no key on the read
  path, changes nothing. Calm, blue. **Most of the app is this.**
- **Mutate** — issue a named, scoped, **recorded** command over SSH. Bordered, amber,
  labelled "witnessed." Every mutation writes its `Event` before it runs.

**Viewing is free; acting is witnessed** — and the line is made physical in the layout.

## The record is two streams

The UI keeps them apart:

- **The audit chain** — discrete *acts* (deploy, grant, restart). Append-only,
  hash-chained, actor-tagged. **This is the spine** (`Event`).
- **The status series** — continuous *health* (load/mem/disk over time). Feeds the
  health narratives and sparklines (`Snapshot`).

Rule that keeps the timeline legible: **show acts always; show status only at
transitions** ("went critical 03:12", "recovered 03:40").

**The acts half is enforced; the transitions half is not built yet.** A routine
sample reports that we *looked*, not that anything *happened*, so it is not an act
and never enters a chain. `Event::STATUS_ACTIONS` names the sample verbs and
`Event.acts` excludes them — one definition, applied to both records: Steward
Console's own rows through the scope, and a box's own timer entries through
`ChainItem#status?`, which the machine-page merge rejects. Nothing is deleted; the
samples stay recorded, they just aren't chain rows. Every chain the UI renders goes
through it — Status, Record, and the machine page.

Surfacing genuine **transitions** is still ahead, and blocked: `Snapshot` is
declared but nothing writes it, so there is no persisted series to derive a
transition from. It arrives with ingestion (#6) — see
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). Until then a
health change shows on the machine, not in the timeline.

## Navigation — every screen is a lens on the one record

The rail is **three bands**, divided by a hairline and nothing else — these are not
eight peers, and the code has always known it:

```
Status · Record                      the spine — the record, and its head
─────────────────────────────
Machines · Installs · Projects       the three rings, bottom-up
─────────────────────────────
Access · App Library · Settings      the surfaces that serve them
```

**The rings read bottom-up, floor first.** The three rings of
[`decisions/console-layers.md`](../../decisions/console-layers.md) — machine view,
placement, tenancy — are each optional *above* the one below, so the nav puts the box
first, placement next to it, and tenancy last as the most declinable. Installs sits
between the box it lands on and the client it is for.

The bands carry **no labels**. The rail has no words of its own beyond the destinations,
and naming the bands would add vocabulary the rest of the docs don't use; a rule is
enough to make a group read as a group.

- **Status** (the "Now" page in this doc's older wording) — the fleet pulse. Calm by default ("12 installs, all healthy · last act 4m
  ago"); exceptions rise to the top, the healthy fold to a count. The unit of concern is
  the **install** — installs in a bad-but-actionable state (failed / machine-unreachable /
  drift), plus those **short of their intention**, lead the page, rendered through the same
  row as the project and fleet lists. A placement gap is a separate test rather than another
  `Install#state` value, and the row shows it *beside* the health glyph, never inside it:
  the glyph is the health of what is running, the gap is the distance from what was asked
  for. Serving *more* boxes than asked for is a gap too, but not an outage — it stays off
  this page and shows on the install.
  Unreachable **machines** follow as the root cause: one down box explains many down
  installs, and it's fixed there.
  **That is the whole page** — what needs you, or nothing. With nothing wrong it says
  *Nothing to report* under a green check, and the counts beneath are the proof it is
  empty because we looked. It used to carry a "Latest" feed of recent acts as well,
  which made the common case read as a wall of things already dealt with; the record
  is one click away in the rail and is better at being a record.
- **Record** — the full timeline. Four dimensions, all ANDed: **who** (actor),
  **what** (action), **for whom** (project), **when** (a time window) — actor,
  project and time as dropdowns offering only values the record holds, action as
  multi-select pills, because picking two or three at once is the normal forensic
  move. Free text searches the rest. The selector grammar (`actor=`, `target=`, …)
  still parses in the text box so a hand-written or shared link keeps working, but
  nothing in the UI requires knowing it. The forensics surface; the thing nobody
  else ships.
- **Projects → Project** — the client lens; observe-only, the shareable client status
  page. A lens over placement, not a container for it: its Installs list is *this
  client's* placements, and the project column is dropped there because it would only
  repeat the page.

  **It leads with a headline**, in the same grammar as every list page: how much is
  placed for this client, and what of it needs a person — *1 install · 2 machines ·
  1 need a look · 1 unreachable*. It is the line that answers "does my client have a
  problem" without scanning three lists. Only this lens's facts.

  **Star stays in the title; Edit and Delete do not.** A destructive control does not
  belong in a page title — deletion moved into a **Project Settings** section at the
  foot, the same closed section the machine view uses. (It is guarded server-side
  besides: a project with live installs or owned machines is refused, naming them.)
  The star is a focus lens rather than a setting, so it stays where you can reach it.

  A section that can only ever say "None" is absent instead — Shared Machines renders
  only when something is shared, the same rule the unreachable cards follow.
- **Installs → Install** — placement, fleet-wide: what should run where. One ring above
  the machine view (which reads a single box) and below Projects. The list carries every
  placement, with the project shown where there is one and a plain dash where there isn't
  — an install with no client is a legitimate state, not missing data. The Install page
  is the app-actions home
  ([`decisions/install-the-app-actions-home.md`](../../decisions/install-the-app-actions-home.md)).

  **Searched and grouped like the fleet list**, from the same mechanism (`Groupings`,
  shared by `MachineGroups` and `InstallGroups`). One `?q=` over what *identifies* a
  placement — its name, the host it serves, the app it came from, and the box it runs
  on — and `?group=` over the axes it *has*: **State** (the default), **App**,
  **Exposure**, **Fleet**, **Project**. No selector grammar in the box: installs carry
  no labels, and every categorical axis is already a chip, so a selector would be a
  second way to ask what the chips answer. Both live in the query string, so a
  narrowed list is a link you can send.

  Ring 2 is this page's floor — an Install *is* the placement ring — and `project` is
  the single chip that reaches out to tenancy, so with tenancy never mounted the list
  loses one chip and nothing else.

  **No act is offered on a box that cannot take one.** `operate` is the key's
  ceiling; reachability is the other half, and every verb travels the same scoped SSH
  connection — so on an unreachable box all six were certain to fail. The gate lives
  in `installs/_acts`, because the rule is about the box rather than about which page
  is asking; the row says why instead.

  **One state word, defined on the target and folded by the install.**
  `InstallTarget#state` is the ladder; `Install#state` is the worst of them. A target
  row used to badge its raw `status`, which knows nothing about the box being
  unreachable or the image having drifted, so a row could read *running* under a
  header that said *unreachable*.

  **The page has two halves, and they must not look alike.** An *Intention* panel states
  what was asked for — `asked for 3 boxes · serving 1` — and a *Where it runs* panel shows
  what the boxes report. The intention panel is dashed and unfilled, borrowing the
  read-only treatment, because the solid card is reserved for things a box actually said.
  The asked-for half stays muted; the serving half carries the colour, since that is the
  part that is true. Merging them into one number is the failure mode the whole layer
  exists to avoid
  ([`decisions/drift-is-surfaced-never-closed.md`](../../decisions/drift-is-surfaced-never-closed.md)).

  When the gap is negative the panel offers **Place on another box** — one act, through
  the ordinary ceremony. Nothing converges on its own, and the button never appears for
  the over-served case, where the honest move is `remove`, not a silent trim.

  The panel also states **exposure** — on the edge, or behind a balancer — because that is
  what decides whether a count above 1 is allowed at all, and **Change what's asked for**
  edits both. That page is styled as intention, not mutate, since saying a different number
  reaches no box.
- **Machines** — the fleet, and the floor of the three rings. The list is about the
  *shape* of the fleet, so **grouping is the primitive, not filtering**: a filter answers
  one question at a time and hides the rest, a grouping answers all of them at once with
  the counts. Group by reachability, scope, edge, fleet, owner, or any label key the
  operator uses. Each grouping is a URL, so a grouped view can be shared, the rule the
  Record destination already follows. There is **no ungrouped view** — a flat fleet list
  answers no question a grouped one doesn't.

  **Each grouping declares which ring it reads**
  ([`decisions/console-layers.md`](../../decisions/console-layers.md)), and that is
  asserted in a test, so one that reaches past the floor has to say so out loud:

  | Ring | Groupings | Why |
  |---|---|---|
  | 1 — machine view | reachability, scope, edge, label key | the box, or the operator on the box |
  | 2 — placement | **fleet** | a machine's balancer is reached *through* its installs |
  | 3 — tenancy | **owner** | an owner is a `Project` |

  The two that reach out are *offered* rather than built into the row. That is the test
  the floor has to pass: **drop a ring and this page loses exactly its own menu items,
  nothing else moves.** No install counts and no project health sit in the rows — the
  floor states only what it owns.

  Above the list, a **headline** gives this layer's story in one line — `14 boxes · 2
  unreachable · 3 not yet seen`. Each list page carries one, and the rule is the same
  everywhere: a headline may state only facts its own ring owns.

  The list **opens grouped by reachability**, because the first question anyone asks a
  fleet is which of it is up, and it costs nothing to answer before being asked. An
  unknown `group=` lands there too, so a stale link degrades to the useful view.

  Reachability leads each row as a single solid dot, but the **shape** differs per state
  as well as the colour — filled, slashed, hollow — so it survives without colour. It
  draws from the `--dot-*` tokens rather than the text ones: these are graphical, answer
  to the 3:1 non-text rule, and are free to carry more saturation than a word may.

  What the box is **for** trails on the right beside the scope marker, where the quiet
  markers live, and it says what the box *carries*, not merely what kind it is — `Host —
  3 apps`, `Load Balancer — 4 hosts`, or a plain `Host` when it carries nothing. Today it
  distinguishes only a **balancer** from an ordinary box, the one role Steward Console
  stores; the role the box itself reports needs ingestion first. Both counts read
  preloaded associations, because a list must not ask the database once per row any more
  than it may ask the *boxes* once per row.

  Every icon that carries meaning explains itself through the shared `.hint` tooltip,
  which appears on **hover and on keyboard focus** and is labelled for a screen reader. A
  native `title` does none of that, and an icon whose meaning is only available to a
  mouse is not accessible. An icon that merely repeats adjacent text stays decorative.

  *Not yet:* grouping by **role**, which is the most natural way to group a fleet and the
  purest layer-1 fact there is. The list does no per-machine live read, and drawing a list
  must never cost N SSH round trips, so it waits on the reported role being persisted —
  ingestion (#6).
- **Machines → Machine** — the box lens, and it is **shaped by the box's role**:
  sections exist because the box says what it was prepared for (`steward status`
  reports `role`), not because the console assumed it. A `balancer` shows no Apps
  section — not greyed out, absent, because that box has no container runtime and
  would refuse a deploy by name. A box that reports no role has never been prepared,
  and an unreachable one reports what runs there as **unknown, not none** — neither
  loses the section, because we do not take a surface away on a guess.

  **The role is a statement, never a control.** `steward prepare <role>` writes it
  once and refuses to convert a prepared box into the other role — you take its apps
  off, uninstall, and prepare again (`blueprint/steward/provision.md`). So the console
  reports it and offers no way to change it. It used to offer a "Make this a balancer"
  button, which wrote a column the box had never agreed to: a `host` so marked would
  accept balanced installs and then be refused by its own box. The column survives as
  our **mirror of the last read** — the fleet list cannot do a live read per row — and
  `Steward::Observe.reconcile` is what writes it. It reads in three states, which are
  not the same thing: the box said so; the box said nothing (**not prepared**, and
  there is a command to fix that); we could not ask (**unknown**, falling back to the
  last read).

  **Identity is two lines, and the room goes to what is running.** Name and badges —
  role first, then reachability, scope, sharing, owner — then one line of facts: the
  hostname the box reports for itself, the address we dial, the clients it serves.
  It was five stacked blocks before the page said anything about the box.

  **Each card does one thing, and carries at most one action, beside its title.**
  Live status (with **Read now**), apps, maintenance, edge. The old page had a
  general-purpose "Mutate · witnessed" card whose prose explained the scope that is
  now a badge in the header, and which held maintenance as a sub-section; maintenance
  is its own card, and the scope sentence is gone because the badge says it.

  **The Apps card is what the box reports, with our record attached.** One list, not
  two: the box's apps are the rows, each linking to its `Install` where we hold one,
  each showing the digest it is *actually* running — truncated, with click-to-copy
  that copies the whole reference rather than the abbreviation. An app the box runs
  that we hold no placement for says **not in our record** (a machine-view deploy
  keeps none, by design, above). A placement we hold that the box does not report is
  named as a gap beneath the list — stated, never closed on its own.

  **An unreachable box does not lay out cards that apologise.** Live status, apps,
  maintenance and the edge card all exist only because we can read the box; when we
  cannot, they are **absent, not dimmed** — there is nothing to dim, because there is
  nothing. One card owns the message: the error, when we last heard from it, and
  **Try again**. It does not need to explain that what runs there is *unknown, not
  none*; nothing is left on the page that could be read as "none", which is the
  stronger version of saying so. **No act is offered**, because every act travels the
  same connection that just failed; a control certain to be refused is worse than no
  control.

  Our own record is a different matter and stays at full strength below, because it
  is not stale — it is simply the only half we still have. The box's half says so in
  **red**: *Box record unavailable — the entries below are ours alone, and end at the
  last read.* Muted would have read as "nothing to see".

  **Machine Settings is a section behind a click.** Ownership and sharing, the key,
  and removal configure the box rather than report on it, so they sit below the
  record in a collapsed section — reaching a destructive control should take a
  deliberate act, the rule the confirms inside it already follow. It is drawn as a
  *section header* (caret, title, rule) and not as a card, because the disclosures
  inside it are cards: a container that looks like its contents reads as one pattern
  repeated. **Remove** is a panel rather than a nested disclosure for the same
  reason — the section is already its gate, and the button carries its own confirm.

  **A machine-view deploy is stateless in the console.** Paste an AppConfig, it goes to
  the box on stdin, and it is *discarded* — no `Install`, no `Project`, no stored spec.
  What is running afterwards is read back from the box, whose record is the only
  record. That is deliberate: a stored copy of the spec would be a second, quieter
  answer to "what is supposed to run here," which is the intention layer's job one ring
  out, where the gap against reality is visible rather than assumed away.

  **A balancer box grows an Edge panel.** It shows the routing table derived from the
  installs that select it — hostname → upstreams — beside the addresses the box *reports*
  fronting, the same two-halves grammar as the intention layer. Applying is
  **Apply Routing**, a witnessed act; nothing reconciles on its own. An unreachable
  balancer reads as *unknown*, never as *fronting nothing*, which is the dangerous
  misreading.

  The console validates only that the config is a JSON object and that its name
  matches the name being deployed under. Everything else is the box's to judge — it
  validates at the render boundary and refuses what it cannot render, and a second copy
  of those rules here would drift from the first.
- **Access** — the rights ledger: who can touch what, at which rung
  (`observe ⊂ operate ⊂ grant`). Read straight off each box through `steward actors`,
  never from a stored copy — `authorized_keys` *is* the ledger, and a mirror of it here
  would be a second answer to "who can act on this box" that could quietly disagree
  with the box. So the page has no model behind it and nothing to keep in sync.

  **One list of keys, grouped — not one card per box.** The row is a *line of a
  ledger* (`AccessLine`), and the same set of lines is read down three axes:

  - **Reach** (the default) — one ordered ladder, most reach first. An ungated line
    is not a rung: a key with no forced command has **no ceiling at all**, which puts
    it *above* `grant` rather than beside it. So the keys Steward did not write lead
    the page **by construction**, not as a banner someone has to look behind.
  - **Box** — who can act on this machine. What the page used to be, now one axis.
  - **Actor** — where does this actor reach? An actor holding `operate` on twelve
    boxes is a fact about blast radius that no per-box view can surface, and the old
    card layout could not answer it at all.

  A line with no forced command is a way onto the box that skips the gate entirely,
  and this is the only screen that can ever show it — so it is said twice: the group
  leads, and a panel says *why* it matters, because under the Box or Actor axis those
  rows are scattered through the list.

  An unreachable box reads as *unknown*, not as *nobody* — the dangerous misreading is
  an empty list meaning "no one has access." Those boxes get their **own panel, never
  rows**: they have no lines to show, and inventing a row for them would be inventing
  an answer. They are also excluded from the "keys on N boxes" count, which counts
  boxes actually read.

  The fingerprint is the field to check a key by — the same string `ssh-keygen -lf`
  prints. Key material is never reproduced. For a hand-added key the holder's handle
  survives nowhere but the raw line, so it is read out of there — but only when the
  line begins with the key type Steward reported, because guessing at a position would
  be inventing an owner for the most dangerous row on the page.

  Observe only. Granting and revoking are acts, and they happen where acts happen.
  Re-reading is a **POST**: it opens an SSH connection to every box in the fleet, and
  a GET must be safe to repeat unasked.
- **App Library** — the curated app catalog (the install front-of-funnel — see
  [`journeys.md`](journeys.md)).
- **Settings.**

## The one page pattern

Every entity — Machine, Install, Project — renders the same shape:

1. **Header** — name · health dot · plain-language narrative · scope/rights badge.
2. **Head** — current state as the latest projection (live status for a Machine; running
   digest + health for an Install).
3. **Chain** — the record filtered to this entity, **as the body of the page, not a
   footer**. Acts plus status transitions, newest first.
4. **Mutate zone** — witnessed actions, visually set apart (the amber "this will be
   recorded" zone).

The inversion: the timeline is not a tab or a bottom-of-page feed. It **is** the page,
and current state is its most recent vertebra.

## How a row reads, and how an entry reads

Two shapes carry nearly every screen, so both are fixed here.

**A list row is a link — all of it.** Every row in `.rows` (machines, installs,
projects, apps) leads somewhere, and the row already lights up on hover, so asking
for the name specifically was a smaller target than the row looked. The name stays
the real anchor — it keeps the `href`, the focus ring and the accessible name — and
its `::after` is stretched across the row. No JavaScript and no clickable `<div>`.
Anything else in the row that can be clicked or hovered — the owner link, the
outbound hostname, buttons, the select box, the tooltip glyphs — is lifted back
above that overlay.

**A record entry reads like an inbox line, not a chain link.** The act is the
subject line and carries the weight; who did it and where it landed are the quiet
second line; when is the right-hand column. Entries are separated by a hairline and
nothing else. They deliberately are **not** drawn joined: the entries share a
record, not a causal thread — a label edit on one project and a deploy on another
box are neighbours by clock alone — and a rail between them drew a relationship
that isn't there. (The *data* is still hash-chained; that claim is made by the
integrity badge, which is evidence, not decoration.)

**One neutral grey for every verb's glyph.** Colour on this page is spent only on
what is genuinely exceptional: a failed act, and an act still running. The glyph
used to go amber on acts that touched a box, decided by a hand-kept list of verb
substrings — but the verb is spelled out beside it now, and a witnessed act already
carries its own tag and its outcome in words. A column of colour repeating what the
words say made the list louder without saying more, and the list behind it rotted
silently (`updated` had fallen out of it, so apply-updates drew as an observe). Both
are gone; nothing replaced them.

**A command to run carries a copy button.** Every command the console prints is
meant to be pasted into a shell on a box, and an `authorize` line carries a whole
public key — selecting one by hand is exactly the operation that half-succeeds and
then fails somewhere unhelpful. `command_block` renders the block and the button
together, in the docs site's shape (`blueprint/design/patterns.md`): a real
`<button>` with an `aria-label` and an `aria-hidden` icon, faintly visible at rest
rather than hidden until hover, copying the exact text shown.

**A list is grouped, never filtered down to one answer.** Both list pages (Machines,
Installs) open on the axis that answers "which of these needs a person" —
reachability for boxes, state for placements — and a grouping shows every answer at
once, with counts, where a filter shows one at a time. There is no ungrouped view: a
flat list answers nothing the grouped one doesn't. The mechanism is one module
(`Groupings`); each page keeps only its own axes, because what a fleet groups by and
what a set of placements groups by are different questions. An unknown `group=`
lands on the default, so a stale link degrades to the useful view rather than to a
flat list or an error.

**One rolled-up state word, defined once.** `Install#state` is the ladder — failed,
unreachable, drift, deploying, pending, running, unplaced — and the row's glyph, the
Status page's exception list, the Installs grouping and the Install page's own badge
all read it, so they agree by construction instead of by four copies. (The badge did
keep its own, shallower ladder for a while, which made the *deep-dive* page for an
install the least accurate thing about it: a drifted install, or one whose box had
gone unreachable, read there as plainly "running".) `Install::EXCEPTION_STATES` names the
three that need a person. A **placement gap** is never folded in: an intention is
not a state (`decisions/drift-is-surfaced-never-closed.md`), so it renders beside
the glyph, never inside it.

**A row states facts about itself; only a fleet may draw relationships between
rows.** The Fleet grouping indents the boxes a balancer fronts beneath it, and that
is honest *there* because the group is that fleet. Under any other grouping the same
tree would be a lie — a group of unreachable boxes is not a fleet, and drawing one
box under another would read as *this one is down because that one is.* So the edge
travels as a per-row fact instead: `behind edge-01` beside the name, true under every
grouping, and dropped inside the fleet tree where the indent already says it.

Because the record is append-only, a summary is never rewritten to fix its case.
Entries are sentence-cased **at the point of reading**, which also brings rows
written before that rule into line.

**`action` is the verb; `summary` is what it touched.** They are two columns and
they must not overlap. An entry renders them as two parts of one sentence — the
verb in bold, then the object — so the act is legible as words, not only as a
glyph: **Deployed** acme-web on devbox. A summary that repeats its own verb produces
"Deployed deployed acme-web", so summaries carry the object alone.

**A verb is one word.** `added`, `removed`, `edited`, `deployed`, `updated`,
`granted`, `promoted` — not "added project" or "applied updates". The object is
already in the summary, and naming it again in the verb only made the Record's
filter pills long and nearly duplicate (`added project` / `added machine` /
`added label` are one act on three nouns). The single exception is `rolled back`,
which English gives no one-word past tense. Pinned in
`test/helpers/action_icon_test.rb`.

Each verb draws one glyph (`ApplicationHelper#action_icon_name`), and the Record's
action pills wear the same glyph the entries do, so a pill and the rows it selects
are one vocabulary. An act's glyph never collides with an outcome's — `circle-check`
is the settled-ok tick and no verb may claim it; `updated` wears a double tick
instead. That is pinned too, because `icon()` renders nothing at all for a name it
does not know, so a typo would silently drop the glyph rather than fail.

Both rules apply to acts recorded **from here on**. Entries written earlier keep the
verb they were recorded with — that is what append-only means — so the icon mapping
still matches the old two-word spellings, and `ApplicationHelper#act_detail` strips
the leading verb an older summary repeats. A verb is a recorded fact and is never
rewritten at display; only its *case* is, and case is not a fact.

## The hero interaction — the mutate ceremony

One component for *any* witnessed act (deploy, rollback, start/stop/restart, remove,
apply-updates):

1. **Compose** — pick what (image digest, target). Only acts that need it (deploy).
2. **Preview the record entry** — show the exact accountable line before it runs:
   `nick · deploy · acme-web · @sha256:abc → db-1`, rendered with the real chain styling,
   nothing written. The record-before-act invariant *is* the confirm dialog.
3. **Confirm** — the friction. Friction is a feature on the dangerous side.
4. **Settle** — the outcome is stamped on the same entry (`pending → ok/failed`). Rollback
   is a *new witnessed act*, never a silent undo.

Verbs come from an allowlist (`Mutation::ACTS`), never raw input. The deploy/rollback path
pipes the desired-state envelope on scoped-SSH **stdin** so secret values never ride the
recorded command line. The settle step reuses the **same timeline component** the observe
side renders — the deploy screen isn't special, it's the record, live. That is how the
record-as-spine model avoids becoming two apps.

> **Live "watch" is still ahead** (a deploy currently blocks until it settles). Streaming
> an act's sub-steps in place — pull → start color → health → flip → drain — needs a
> Steward sub-step protocol; tracked in the open roadmap.

## Principles to hold

- **Viewing is free; acting is witnessed** — every mutate confirm shows the record entry
  it will write.
- **State is the head of the record** — stop splitting "what is" from "what happened."
- **Calm by default; lead with exceptions** — no wall of green.
- **Plain-language health narratives** — on-brand with the Orwellian naming rule.
- **The rights ledger is visible** — authorize/revoke as a surface, not buried config.
- **Friction on mutate; frictionless on observe** — but never *unasked*. Viewing is
  free of consequence, not free of cost: a machine page reads its box over SSH, and
  `/access` reads every box in the fleet. So a read the operator did not ask for must
  not happen. Turbo's hover prefetch is **off** (`<meta name="turbo-prefetch">`), and a
  read that bypasses the cache — `Read Now` — is a **POST**, because a GET has to be
  safe to repeat unasked and a pointer moving across a link is not a decision.
- **No mode-switching** — one app, one lens that widens (Dispatcher dropped as a concept;
  see [`decisions/ui-shape.md`](../../decisions/ui-shape.md)).

## Theme

CSS custom-property tokens (color, spacing, type); a cohesive WCAG-AA palette; the ported
lucide icon set; **mono = machine truth** (raw box values render monospaced).

Appearance has **two axes**, both stored on the `User` and rendered onto `<html>` by the
layout:

- **Theme** — a named set of token values (`Theme::ALL`). `steward` is the default and
  the reference: near-black on near-white with the one yellow accent, the docs site's
  palette from [`blueprint/design/tokens.md`](../design/tokens.md). Yellow stays graphic
  on light — the interactive colour is ink, and yellow marks position (the active rail
  item, the focus halo). Its dark half turns the voltage up: neon yellow accent, orange
  mutate, neon-green health, a purple rail spark. **Blue stays blue** — observe means the
  same thing in both modes, and a mode that re-assigns meaning is a different theme.
- **Mode** — `light`, `dark`, or `system` (the default), which follows the operator's OS.

Both are set from **Settings**; the rail keeps a light/dark toggle that persists the same
field. Appearance is **personal, not fleet policy**, which is why it lives on the user and
not on `Setting` — and it is **not a recorded act**: it touches no box and changes nothing
about the fleet.

Preference lives in **one place only** — the user record. Nothing is cached in the
browser, so there is no stored copy to disagree with the server and no flash of the wrong
theme; the theme is correct in the first byte. The single exception the server cannot
resolve is `system`, which a pre-paint script turns into a concrete mode by asking the OS.
It *reads* the preference off the element and never writes one.

Adding a theme is two steps and touches nothing else: one entry in `Theme::ALL`, one pair
of blocks in `tokens.css`. Nothing outside that file learns a theme's name — which is what
the semantic token layer is for, and what leaves the door open to operator-defined themes. The universal **label** system (segmented
key/value tags, polymorphic on Project/Machine/App) is the operator's own grouping axis,
distinct from the system's status/scope badges — see
[`data-model.md`](data-model.md).

## Build state

The shape above is settled. What is realized vs. still ahead — ingestion (#6), the
generic focus/pin lens (#10), the secret/env panel (#14), live-watch (#15), Access (#16),
the chain-integrity badge (#17), the shareable client view (#18), the command palette
(#19), and Steward Console-deploys-Steward Console (#20) — is tracked wave by wave in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). When a screen lands and
settles, its canonical description moves here.
