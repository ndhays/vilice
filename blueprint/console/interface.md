# Steward Console — Interface

> How Steward Console looks and behaves: the record is the spine, observe and mutate are
> kept apart, and every screen is a lens on the one record. The *why* — and the shapes
> rejected — is in [`decisions/ui-shape.md`](../../decisions/ui-shape.md).

**Status:** Canonical (the shape is settled and largely built — Waves 1–3). The build
roadmap and the screens still ahead live in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). Last touched 2026-09-29.

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
- **Mutate** — issue a named, scoped, **recorded** command over SSH. Bordered, violet,
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
Machines · Apps · Projects           the three rings, bottom-up
─────────────────────────────
Access · App Library · Settings      the surfaces that serve them
```

**What things are called.** The page and the code use the same words. An **App**
(`App`) is what an operator means by "the app": a template configured for a client. One
app on one box is a **Placement** (`Placement`). A Library entry is an **App Template**
(`AppTemplate`), and the Library keeps its name, the **App Library**.

**The rings read bottom-up, floor first.** The three rings of
[`decisions/console-layers.md`](../../decisions/console-layers.md) — machine view,
placement, tenancy — are each optional *above* the one below, so the nav puts the box
first, placement next to it, and tenancy last as the most declinable. Apps sits
between the box it lands on and the client it is for.

The bands carry **no labels**. The rail has no words of its own beyond the destinations,
and naming the bands would add vocabulary the rest of the docs don't use; a rule is
enough to make a group read as a group.

- **Status** (the "Now" page in this doc's older wording) — the fleet pulse. Calm by default ("12 apps, all healthy · last act 4m
  ago"); exceptions rise to the top, the healthy fold to a count. The unit of concern is
  the **app** — apps in a bad-but-actionable state (failed / machine-unreachable /
  drift), plus those **short of their intention**, lead the page, rendered through the same
  row as the project and fleet lists. A placement gap is a separate test rather than another
  `App#state` value, and the row shows it *beside* the health glyph, never inside it:
  the glyph is the health of what is running, the gap is the distance from what was asked
  for. Serving *more* boxes than asked for is a gap too, but not an outage — it stays off
  this page and shows on the app.
  An app short of its intention **with no free box to close it** is called out once,
  above the rows: that is a different ask from the rest of the list — a click on the
  app versus going and getting a box — and it is fixed somewhere else, which is the
  same reason unreachable machines get their own section. Computed against one preloaded
  pool, because a list must not ask the database once per row.
  Unreachable **machines** follow as the root cause: one down box explains many down
  apps, and it's fixed there.
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
  page. A lens over placement, not a container for it: its Apps list is *this
  client's* placements, and the project column is dropped there because it would only
  repeat the page.

  **It leads with a verdict — Status's answer, scoped to one client.** Either there is
  something to deal with or there is not, and the page says which before it says
  anything else: *Nothing to report* under a green check, or *1 app needs a look ·
  1 box unreachable* under an alert. The counts sit underneath as the proof it was
  looked at, the same role they play on Status. Only this lens's facts.

  Unlike Status it keeps its lists below either way — a client page is also where you
  go to find a specific app, not only to learn whether anything is wrong.

  **Star stays in the title; Edit and Delete do not.** A destructive control does not
  belong in a page title — deletion moved into a **Project Settings** section at the
  foot, the same closed section the machine view uses. (It is guarded server-side
  besides: a project with live apps or owned machines is refused, naming them.)
  The star is a focus lens rather than a setting, so it stays where you can reach it.

  A section that can only ever say "None" is absent instead — Shared Machines renders
  only when something is shared, the same rule the unreachable cards follow.
- **Apps → App** — placement, fleet-wide: what should run where. One ring above
  the machine view (which reads a single box) and below Projects. The list carries every
  placement, with the project shown where there is one and a plain dash where there isn't
  — an app with no client is a legitimate state, not missing data. The App page
  is the app-actions home
  ([`decisions/install-the-app-actions-home.md`](../../decisions/install-the-app-actions-home.md)).

  **Logs sit with the box's name, not with the verbs beside it**, because they are not
  one of them: reading is `observe` and every verb there is `operate`. So the link is
  offered on a box whose key **cannot act** — the moment you most want to look is the
  moment you are least able to touch. It opens its own frame, kept apart from the
  ceremony's: one is the violet *this will be recorded* zone and the other is a plain
  read, and nobody should have to work out which they are looking at. The body wears
  the same `pre.raw` terminal treatment every other piece of box output does, scrolls
  inside its own frame both ways, and says out loud that nothing was cached and nothing
  recorded. The only control is the tail size — `podman logs` is a passthrough, and
  there is nothing to filter here that `grep` would not do better on the far side.

  **Searched and grouped like the fleet list**, from the same mechanism (`Groupings`,
  shared by `MachineGroups` and `AppGroups`). One `?q=` over what *identifies* a
  placement — its name, the host it serves, the app it came from, and the box it runs
  on — and `?group=` over the axes it *has*: **State** (the default), **App**,
  **Exposure**, **Fleet**, **Project**. No selector grammar in the box: apps carry
  no labels, and every categorical axis is already a chip, so a selector would be a
  second way to ask what the chips answer. Both live in the query string, so a
  narrowed list is a link you can send.

  Ring 2 is this page's floor — an App *is* the placement ring — and `project` is
  the single chip that reaches out to tenancy, so with tenancy never mounted the list
  loses one chip and nothing else.

  **No act is offered on a box that cannot take one.** `operate` is the key's
  ceiling; reachability is the other half, and every verb travels the same scoped SSH
  connection — so on an unreachable box all six were certain to fail. The gate lives
  in `apps/_acts`, because the rule is about the box rather than about which page
  is asking; the row says why instead.

  **One state word, defined on the placement and folded by the app.**
  `Placement#state` is the ladder; `App#state` is the worst of them. A target
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
  | 2 — placement | **fleet** | a machine's balancer is reached *through* its apps |
  | 3 — tenancy | **owner** | an owner is a `Project` |

  The two that reach out are *offered* rather than built into the row. That is the test
  the floor has to pass: **drop a ring and this page loses exactly its own menu items,
  nothing else moves.** No app counts and no project health sit in the rows — the
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
  accept balanced apps and then be refused by its own box. The column survives as
  our **mirror of the last read** — the fleet list cannot do a live read per row — and
  `Steward::Observe.reconcile` is what writes it. It reads in three states, which are
  not the same thing: the box said so; the box said nothing (**not prepared**, and
  there is a command to fix that); we could not ask (**unknown**, falling back to the
  last read).

  **Identity: the name and one live signal, then a short labelled list.** Beside the
  name sits the health line — a dot and plain words: *Online*, or what is wrong (*disk
  91% — running low*), or *Unreachable*. No pills in the header; on the box the console
  runs on, the leading glyph is a location pin that says *you are here* on hover. What
  the box *is* sits beneath as a two-column list, labels left, values right, always in
  the same order: **Address · Role · Owner · Sharing**. Two more rows appear only when
  they are news: **Box says** when the hostname the box reports differs from the name
  (the name mirrors the box, so usually it does not), and **Also serves** for clients
  beyond the owner. Access is not listed; the Operate zone says it. A missing owner or an
  unprepared role reads in red.

  **Two zones, side by side: Observe, then Operate.** Under the header the page splits
  into two columns (stacked on a narrow screen), each headed in its own colour — blue
  **Observe**, violet **Operate**. *Where a control sits says what kind it is*
  ([`what-the-console-is-for.md`](../../decisions/what-the-console-is-for.md)).

  **Plain on the surface, exact underneath.** The zones interpret; the command and its
  raw reply are one step down — in the preview, the record, and a card's raw disclosure.
  The one bridge on the surface is the button: **a command button carries the Steward
  mark and the verb** — `status`, `apply-updates`, `route`, `deploy`, `remove` (and on
  the App, `deploy` `rollback` `start` `stop` `restart` `remove`) — mono, lowercase,
  **filled**: violet for an act, blue for a read, red for one that takes something away.
  Nothing that does not call Steward looks like it. A plain sentence beside it says why
  you would press it. The full command, flags and all, is shown in the preview, copyable,
  before anything runs.

  - **Observe holds no act.** Live status, with when it was read beneath its title
    (*Read 2 minutes ago · cached*), a `status` button to read again, and **Raw status
    output** at its foot — the command in bold, then the JSON it returned; maintenance (the window,
    and the updates waiting, by name); the apps the box reports; **Backups** — each app
    and the record, last backed up when, or *never*, or *last attempt failed* with the
    reason, and *Nothing on this box is backed up* when no repo is set (from `status`'s
    `backups`; absent when the box's steward predates it); **Certificates** — each served
    hostname, valid and days to expiry, amber inside 14 days, red when not served or not
    trusted (from `status`'s `certs`); the edge table on a balancer; the **Record** card
    (chain intact, entry count, last entry); and beneath the cards, as a list rather than
    a card, **Who can reach this box** — its ledger via `steward actors`, the Access
    page's rows, and *Could not read the ledger* rather than an empty list when unread.
  - **Operate lists every act the box can take**, each a sentence and a button:
    `apply-updates`, `route` on a balancer, `deploy` from a pasted spec, and `remove`
    per app the box reports. An act with nothing to do (no updates waiting) **keeps its
    button, inert** — the zone reads the same whatever the box's state. Commands come
    from `Mutation.command`, the same builder that sends them. App lifecycle is not here —
    it lives on the App. The ceremony opens **inside this zone**.
  - On an observe key, Operate is one large statement — **No operate access** — and on
    an offline box, **Nothing can be sent**.

  **The Apps card is what the box reports, with our record attached.** One list, not
  two: the box's apps are the rows, each linking to its `App` where we hold one,
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
  the box on stdin, and it is *discarded* — no `App`, no `Project`, no stored spec.
  What is running afterwards is read back from the box, whose record is the only
  record. That is deliberate: a stored copy of the spec would be a second, quieter
  answer to "what is supposed to run here," which is the intention layer's job one ring
  out, where the gap against reality is visible rather than assumed away.

  **A balancer box grows an Edge panel.** It shows the routing table derived from the
  apps that select it — hostname → upstreams — beside the addresses the box *reports*
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
  boxes actually read. Every one is named, but **grouped by reason and run inline** —
  the failing case is usually the whole fleet failing the same way, and one line per
  box turns fifty of them into a screenful nobody reads.

  The fingerprint is the field to check a key by — the same string `ssh-keygen -lf`
  prints. Key material is never reproduced. For a hand-added key the holder's handle
  survives nowhere but the raw line, so it is read out of there — but only when the
  line begins with the key type Steward reported, because guessing at a position would
  be inventing an owner for the most dangerous row on the page.

  Observe only. Granting and revoking are acts, and they happen where acts happen.
  Re-reading is a **POST**: it opens an SSH connection to every box in the fleet, and
  a GET must be safe to repeat unasked.
- **App Library** — the curated app catalog (the app front-of-funnel — see
  [`journeys.md`](journeys.md)).

  **A release must be digest-pinned.** The box refuses an unpinned image
  (`steward/internal/app/deploy.go`), so a floating tag in the library is a release
  that *looks* installable and is rejected at the far end, after someone has built a
  placement on it — the same shape as the balancer toggle that wrote a column the box
  never agreed to. `Version` mirrors `validDigestPin` exactly, doubled-prefix case
  included, and the form carries the pattern so the browser catches it first.

  **The declaration read back *is* the Environment panel; editing is behind a
  toggle.** The chip editor is quick to change and hard to audit, and the mistake
  that matters is a variable that should have been marked secret and was not: its
  value is then written to an append-only record and cannot be taken back. So the
  resting state is the auditable form — two alphabetical columns, **Written to the
  record** and **Never recorded**, split by what actually happens to the value, with
  secret files counted in the second because they are off-record by definition.
  Editing reveals the chips in place. Nothing is saved until **Save Inputs**, so
  closing an editor that has been changed *discards* those edits — and the button says
  which: **Done** when untouched, **Cancel** once anything has changed, and cancelling
  puts the form back the way the server sent it. Calling it "Done" either way claimed
  the opposite, and the read-back underneath would have shown the saved state, making
  it look as though the edits had landed.

  The columns name the *consequence* rather than the word "secret", because the
  failure is not knowing what the flag does. They are drawn as one card split by a
  hairline — the split is the whole point, so it is drawn rather than left to
  whitespace — and the names read at body size, because you are checking each one
  rather than glancing at a block.

  **Tabs were considered and rejected** for this panel. The secret flag is a property
  *of* a variable, not a category of variable, so splitting the two across tabs would
  put the comparison you need to make on two screens you can never see at once —
  which is the same list twice with the check removed. Hiding half a security-relevant
  declaration behind a click makes not-noticing easier, and not-noticing is the
  failure.
- **Settings.**

## The one page pattern

Every entity — Machine, App, Project — renders the same shape:

1. **Header** — name · health dot · plain-language narrative · scope/rights badge.
2. **Head** — current state as the latest projection (live status for a Machine; running
   digest + health for an App).
3. **Chain** — the record filtered to this entity, **as the body of the page, not a
   footer**. Acts plus status transitions, newest first.
4. **Mutate zone** — witnessed actions, visually set apart (the violet "this will be
   recorded" zone).

The inversion: the timeline is not a tab or a bottom-of-page feed. It **is** the page,
and current state is its most recent vertebra.

## The form pattern

Entity pages have one shape; so do the forms that create them. **`machines/new` is the
reference** — the smallest complete example — and every other `.stack-form` is that shape
with more in it. It is written down because the two biggest forms had drifted into
different vocabularies: one grouped its fields under legends and one ran them together,
one put errors at the top and one put them after the first field.

1. **Errors at the top**, always. An error is the reason the page is on screen again;
   sitting it after the first field puts the answer below the question.
2. **A run of `fieldset.step`s** — one concern each, under a plain-language legend. No
   field hangs outside a step. A legend takes a `hint` when the concern has a
   consequence the label cannot carry.
3. **The concrete thing leads; tenancy comes last.** `apps/new` never asks you to
   invent a client before you have said what you are placing, and `machines/new` asks
   for the box's address before its owner. Optional context does not get to go first.
4. **Radio cards carry a hint only when the label cannot carry the choice.** *Operate*
   and *Grant* are not tellable apart from one word, and the difference is what a stolen
   key could do — so they keep their sub-copy. *Single machine* / *Fleet* and *On the
   edge* / *Behind a balancer* are the whole choice already, so they use `.plain` and
   say nothing further. A sentence that restates its label is noise in the one place a
   reader is trying to decide.
5. **The submit wears its act's glyph**, not a picture of the noun — `added machine`
   draws `plus`, the same glyph as the button that led there. This is the act-glyph rule
   above, applied to the button that opens the act.

The vertical rhythm is three tokens in `tokens.css` — `--tight` (a label to the thing it
labels), `--gap` (two things inside one step), `--step` (one step to the next) — and the
ordering is the whole point. When a within-step gap grows to the size of a between-step
gap, the steps stop reading as steps and the page is one long column of fields. Pinned in
`test/controllers/machines_controller_test.rb`, because a vocabulary nothing checks is one
that drifts apart again.

## How a row reads, and how an entry reads

Two shapes carry nearly every screen, so both are fixed here.

**A list row is a link — all of it.** Every row in `.rows` (machines, apps,
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

**An entry reads at three levels.** The plain line — what happened, by whom, where,
when — is the reading. An act that ran a steward command leads it with a **stamp** of
that command's verb — the button that was pressed, drawn flat (square corners, no hover,
no pointer) so it reads as a record of a press and never as a thing to press. The door
the act came through sets the stamp (`ChainItem#via`): **filled** violet with the mark
when this console sent it; **dashed yellow with a terminal glyph**, tagged *on the box
itself*, when it ran there rather than through a scoped key (Steward records a local run
under `operator`); **outlined**, tagged *witnessed*, for any other key. An act recorded
here that sent nothing keeps its plain past-tense verb.

Not every box entry is a command, and none is drawn as one that is not (`ChainItem#kind`):

- A **refusal** (`scope: deny`) reads *refused snapshot — binary unrecognized*, in red,
  with no stamp — nothing ran. Its command line is the verb that was refused.
- A **step** — a note a command wrote about its own work (`prepare-role`,
  `authorize-binary`, `deploy-spec`) — is folded under its command as *Also recorded*,
  so one `prepare` is one line, not three.

The machine page's timeline is assembled by `Chain.for_machine`, which also says each
thing once: an act this console sent is **one line** — our event (the person, the
outcome, the reply) carrying the box's own entry for it (matched on verb, within two
minutes) — and a **run of the same entry** (a timer refused every minute) is one line
with a count, *× 40 · since 2 days ago*.

Beneath the plain line, the **command that ran**, in bold mono: `steward apply-updates
--json` for an act the console sent (from `Event.raw["command"]`), `steward deploy app1`
for a box entry (its verb and arguments, read straight off the entry). An act recorded
here that sent nothing to a box says *recorded here · no command sent to a box*. The
command opens to the **raw**: *Also recorded* (its steps), *Output* (`Event.output`; on a
failure with no reply, the reason), *Raw record entry*, and — for an act the console sent
— *The box's record entry*, whose seq and hash are the proof the box wrote it down before
it ran. The same shape as a card's *Raw status output*: plain on the surface, exact one
step down. Long tokens — a public key, a digest — are shortened from the middle in the
plain line and kept whole below.

**A command to run carries a copy button.** Every command the console prints is
meant to be pasted into a shell on a box, and an `authorize` line carries a whole
public key — selecting one by hand is exactly the operation that half-succeeds and
then fails somewhere unhelpful. `command_block` renders the block and the button
together, in the docs site's shape (`blueprint/design/patterns.md`): a real
`<button>` with an `aria-label` and an `aria-hidden` icon, faintly visible at rest
rather than hidden until hover, copying the exact text shown.

**A list is grouped, never filtered down to one answer.** Both list pages (Machines,
Apps) open on the axis that answers "which of these needs a person" —
reachability for boxes, state for placements — and a grouping shows every answer at
once, with counts, where a filter shows one at a time. There is no ungrouped view: a
flat list answers nothing the grouped one doesn't. The mechanism is one module
(`Groupings`); each page keeps only its own axes, because what a fleet groups by and
what a set of placements groups by are different questions. An unknown `group=`
lands on the default, so a stale link degrades to the useful view rather than to a
flat list or an error.

**One rolled-up state word, defined once.** `App#state` is the ladder — failed,
unreachable, drift, deploying, pending, running, unplaced — and the row's glyph, the
Status page's exception list, the Apps grouping and the App page's own badge
all read it, so they agree by construction instead of by four copies. (The badge did
keep its own, shallower ladder for a while, which made the *deep-dive* page for an
app the least accurate thing about it: a drifted app, or one whose box had
gone unreachable, read there as plainly "running".) `App::EXCEPTION_STATES` names the
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

**One glyph, one meaning — nouns too.** The rule is not only about verbs. `earth` means
*faces the public internet*: the go-live buttons, and an app exposed on the edge. It
used to also mark a box **prepared as a balancer**, so the same glyph stood for the edge
in one place and for the thing in front of the edge in another. The balancer now draws
`network` — one front, many backs — everywhere it is named: the role badge, the exposure
picker, and the app's intention chip. Its opposite, `edge`, is drawn in the same
grammar (the world above, one box below, nothing between) so the two read as one pair
answering one question, and `earth` is left meaning only *reachable from the public
internet*: the go-live buttons. In the same spirit a **Fleet** is drawn as
`hard-drives`, three of the `hard-drive` a single machine draws, because a fleet is a
count of the same thing and not a different kind of thing
([`decisions/one-primitive-composed.md`](../../decisions/one-primitive-composed.md)).

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

**`reached` is not `ok`.** The transport reports the two separately, because "we never
got to the box" and "the box answered and refused" are different failures with different
fixes, and the raw SSH output names neither. `ssh` exits **255** when ssh itself could not
get through; any other non-zero status is the remote command's own, and an unreadable
reply is still a reply. A failed act that never reached its box has `Machine#connection_hint`
appended to the alert — *the authorize line has most likely not been run* for a box that has
never answered, *check the box and the provider's own firewall* for one we had and lost.
That firewall is the biggest gotcha in
[`what-could-go-wrong.md`](../../decisions/open/what-could-go-wrong.md), and this is where
it lands.

The confirm step says the same thing **before** the press: a box that has never answered
carries a caution and its authorize line, copyable. It is a **warning, never a block** —
`last_seen_at` is a reading, and a box authorized a minute ago has not been observed yet
and looks identical. The act stays yours to witness; the failure just stops being a
surprise. And it is still recorded either way: we tried, so it is written, and it settles
`failed` — record-before-act does not bend for an act we expected to fail.

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
