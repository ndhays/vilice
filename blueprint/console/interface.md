# Vilice Console — Interface

> How Vilice Console looks and behaves: the record is the spine, observe and mutate are
> kept apart, and every screen is a lens on the one record. The *why* — and the shapes
> rejected — is in [`decisions/ui-shape.md`](../../decisions/ui-shape.md).

**Status:** Canonical (the shape is settled and largely built — Waves 1–3). The build
roadmap and the screens still ahead live in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). Last touched 2026-10-05.

---

## What it calls itself

**"Vilice Console" is the Rails app's name, not a product name.** The UI says
**Vilice** and nothing else: one product, one name, the same one you type at a
shell. The chrome wears the canonical wordmark from
[`blueprint/design/logo.md`](../design/logo.md) — the mark, then `vilice` in mono,
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
`vilice`, so `_vilice@host:22` is noise — drop it) and showing the box's reported name
plainly rather than guarding it with a match/mismatch check (the SSH connection is already
verified; a wrong box surfaces on its own).

## The spine in two halves: observe vs mutate

Everything Vilice Console does is one of two things, kept apart on purpose — Vilice's scope
ladder surfaced in both the UI and the architecture (see
[`overview.md`](overview.md) and `app/services/vilice.rb`):

- **Observe** — read the record Vilice ships. Zero-privilege: holds no key on the read
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
`Event.acts` excludes them — one definition, applied to both records: Vilice
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
  — an app with no client is a legitimate state, not missing data. The App page lists
  each placement with its lifecycle verbs
  ([`decisions/install-the-app-actions-home.md`](../../decisions/install-the-app-actions-home.md)),
  and each placement's box name leads to that app's page on the box, which holds the same
  verbs beside what the box reports. Two places for one act is an open question — see
  [`ui-roadmap.md`](../../decisions/open/ui-roadmap.md).

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
  `Placement#state` is the ladder; `App#state` is the worst of them. A placement
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
  distinguishes only a **balancer** from an ordinary box, the one role Vilice Console
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
  sections exist because the box says what it was prepared for (`vilice status`
  reports `role`), not because the console assumed it. A `balancer` shows no Apps
  section — not greyed out, absent, because that box has no container runtime and
  would refuse a deploy by name. A box that reports no role has never been prepared,
  and an unreachable one reports what runs there as **unknown, not none** — neither
  loses the section, because we do not take a surface away on a guess.

  **The role is a statement, never a control.** `vilice prepare <role>` writes it
  once and refuses to convert a prepared box into the other role — you take its apps
  off, uninstall, and prepare again (`blueprint/vilice/provision.md`). So the console
  reports it and offers no way to change it. It used to offer a "Make this a balancer"
  button, which wrote a column the box had never agreed to: a `host` so marked would
  accept balanced apps and then be refused by its own box. The column survives as
  our **mirror of the last read** — the fleet list cannot do a live read per row — and
  `Vilice::Observe.reconcile` is what writes it. It reads in three states, which are
  not the same thing: the box said so; the box said nothing (**not prepared**, and
  there is a command to fix that); we could not ask (**unknown**, falling back to the
  last read).

  **Identity: the name and one live signal, then a short labelled list.** Beside the
  name sits the health line — a dot and plain words: *Online*, or what is wrong (*disk
  91% — running low*), or *Unreachable*. No pills in the header; on the box the console
  runs on, the leading glyph is a location pin that says *you are here* on hover (the
  box's reported `machine_id` matches the console's own: `/etc/machine-id`, or
  `VILICE_SELF_MACHINE_ID` set by hand when the console runs in a container). What
  the box *is* sits beneath on **one line, as a row of bordered cells**, label over
  value, always in the same order: **Address · Role · Owned by · Used by**, with the
  **Settings** button right beside the table. Ownership reads as a sentence
  fragment — *project Acme*, or *no project* — because a box is owned by a project, not
  by a person. Two more rows appear only when
  they are news: **Box says** when the hostname the box reports differs from the name
  (the name mirrors the box, so usually it does not), and **Also serves** for clients
  beyond the owner. Access is not listed; its chip says it. A missing owner or an
  unprepared role reads in red.

  **A quick view, then one level down.** The machine page is for looking. It shows how
  the box is and what runs on it, and each leads one level down: a status chip to
  the **Machine Status** page, an app line to that app's page. The detail and the acts
  are down there, beside what they act on
  ([`acts-sit-with-what-they-act-on.md`](../../decisions/acts-sit-with-what-they-act-on.md)).
  Nothing on the machine page is folded away.

  Under the header, in order:

  - **Status**, the quick view. **The whole card is the link to Machine Status**; the
    things inside it that do something of their own sit above that link. Its head is the
    title, when the box was read (*Read 2 minutes ago · cached*), and — right beside
    those words, so it is plain what it re-reads — the `status` button.
    **Memory and disk are bars**: the label, the percentage and the amounts (*6.4 GB of
    16 GB*) on one line, and beneath it a bar as wide as the usage, cut into small blocks
    like a level meter. The fill is
    green, then amber, then red as it passes the same thresholds the health line uses.
    Load and uptime are words beside them. Then **everything else about the box, on one
    line of chips**: an icon and a few words each, calm when well, bordered in the
    warning colour when not, with the full sentence on hover. Each chip is the link to
    its part of Machine Status. No act is offered here.
  - **Apps on this box** — one line per app the box reports (below), with **`deploy`**:
    putting an app on the box is not an act on any one app, so it stays with the list.
    On a balancer its place is taken by the **Edge** card — the derived table, what the
    box reports fronting, and **`route`**.
  - **The record**, as the body of the page.

  The chips, and what each says (`MachineSectionsHelper`; the chip shows the short form,
  Machine Status the full one):

  | Chip | When all is well | Coloured when |
  |---|---|---|
  | **Hardening** (a lock) | *Hardened*, or *Hardening not checked* | a property has drifted |
  | **Maintenance** | *Up to date* | updates are waiting (*3 updates*), or a restart is required |
  | **Registries** | the hosts logged into, or *No registries* | never |
  | **Certificates** | *3 certs valid* | one is close to expiry, not served, or not trusted |
  | **Record** | *Record intact* | the chain is broken or unread; the record's backup failed, never ran, or has no repo |
  | **Access** | *2 keys* | the ledger could not be read, or a key has no forced command |

  Registries is absent on a balancer, and Certificates when the box serves no hostname.

  **Machine Status is its own page** (`/machines/:id/status`): the box itself, in full.
  It has one part per chip above, in the same order, each a card that **leads with the
  full summary**, then the detail, then the acts on it:

  - **Status** — the numbers, the hardening line, and **Raw status output**: the command
    in bold, then the JSON it returned.
  - **Maintenance** — the window, the updates waiting, by name, and **Restart required**
    — with the packages that asked and what happens next: *the box restarts itself at
    04:00*, or *restart it on the box*, since Vilice has no restart command. Its act is
    **`apply-updates`**.
  - **Registries** — host and username, never the secret (from `status`'s `registries`).
    A registry login belongs to the box
    ([`registry-credentials.md`](../../decisions/registry-credentials.md)), so its acts
    are here: **`registry-logout`** beside each, and **`registry-login`**, a form (below).
  - **Certificates** — each served hostname, valid and days to expiry, amber inside 14
    days, red when not served or not trusted (from `status`'s `certs`), and **the app
    the hostname belongs to**, linked. Caddy keeps certificates for the whole box, but
    each is one app's, so the same rows appear on that app's page. No act.
  - **Record** — chain intact, entry count, last entry, and when the record itself last
    backed up off the box. Its act is **`backup`** (`backup --machine`). With no repo set
    it says *The record is not backed up* and offers nothing.
  - **Access** — the box's ledger via `vilice actors`, the Access page's rows, and *Could
    not read the ledger* rather than an empty list when unread.

  It is one request, from the same cached reads the machine page makes, with its own read
  line; reading again returns to it. An act's preview opens in the part it was pressed
  in, and returns to the page when it settles. An act with nothing to do (no updates
  waiting) **keeps its button, inert**. On an **observe key** the page reads the same and
  offers no act. An unreachable box shows one card with the error.

  *Which kind of control it is reads off the button*: **a command button carries the
  Vilice mark and the verb**, mono, lowercase, **filled** — blue for a read, violet for
  an act, red for one that takes something away. Nothing that does not call Vilice looks
  like it. A plain sentence beside it says why you would press it.

  **Plain on the surface, exact underneath.** The page interprets; the command and its
  raw reply are one step down — in the preview, the record, and the raw disclosure. The
  full command, flags and all, is shown in the preview, copyable, before anything runs.
  Commands come from `Mutation`, the same builder that sends them.

  **The Apps card is what the box reports, with our record attached.** One list, not
  two: the box's apps are the rows, one line each — the name, **how it is doing** (a dot
  and the box's own words: green for *Up 6 minutes*, grey for *stopped*, red for anything
  else), **where it answers** (its first hostname, a link that opens the app in a new
  tab, and *+N* for the rest, leading to its page), **how much of the box's memory it is
  using** (a small bar and the amount — a share of the box, since an app has no limit of
  its own), **two marks** that stay quiet unless something is wrong (a shield for its
  certificates, a drive for its backup, each saying the whole thing on hover), the
  project where we hold one, and the digest it is *actually* running,
  truncated, with click-to-copy that copies the whole reference. An app the box runs
  that we hold no placement for carries no mark for it here — a machine-view deploy
  keeps none, by design, above, so it is an ordinary state — and its own page says so.
  **A stopped app stays in the list**: it is still deployed, and its page is the way to
  start it. A placement we hold that the box does not report is named as a gap beneath
  the list — stated, never closed on its own.

  **Every app on a box has its own page** (`/machines/:id/apps/:name`), and the line
  leads to it. The app is named by what the box calls it, so an app we hold no `App`
  for has the page too. **It has the shape of Machine Status**: the name and state, the
  facts on one line, when the box was read with `status` beside it, then a part for each
  thing about the app — each leading with how it is, then the detail, then the acts.

  The facts, as one row of bordered cells: **Box · Answers at · Image · Placement**.
  *Answers at* is every hostname, each a link that opens the app in a new tab (a
  wildcard is shown, not linked). *Placement* is a link to the `App`, or *none*.

  The parts:

  | Part | Leads with | Holds | Acts |
  |---|---|---|---|
  | **Running** | the box's words for its state | how much of the box's memory it is using, as a bar; **Logs**, a read, offered on a key that cannot act | `restart`, `stop`, `start` |
  | **Deploy** | *Running @abc123…* | — | `deploy`, `rollback` |
  | **Certificates** | *2 valid* | each of its hostnames and the certificate it hands out | — |
  | **Backups** | *Backed up 5 hours ago* | the reason, when the last one failed | `backup`, `restore` |
  | **Remove** | what it takes and what it leaves | — | `remove` |

  - **`deploy`**: with an `App` in our record it sends that App's spec at an image you
    pick (the ceremony's compose step); with none there is no stored spec, so it opens
    the box's own deploy form with the name filled in.
  - **`rollback`** is inert when the box says there is no earlier image to go back to.
  - **`restore`** is red, and inert until there is a snapshot to restore. With no repo
    set on the box, Backups says so and offers nothing. Backups follow the app; the
    machine keeps only the record's own.
  - **`remove`** is red. When it settles the page returns to the machine, since the
    app's page has nothing left to show.
  - Certificates is absent when the box reports none for the app, and Backups when the
    box's vilice predates the fact.

  A name the box does not report gets the page too, saying so, rather than an error —
  and where we hold a placement for it, that is the gap, with `deploy` to close it. An
  unreachable box shows one card with the error and no act. The page reads the same
  cached `status` the machine page does; it is one request, and reading again returns
  to it.

  **Logging a box in to a registry is a form, not a ceremony act**, because it carries a
  password and the ceremony's preview travels in a URL
  (`Machines::RegistriesController`). The form is the preview: it shows the command and
  says what is recorded — who, the registry, the username. The password goes to the box
  once, on stdin; the console keeps it in no column, no `Event`, and no log.

  **The page never waits on the box.** It is two requests. `show` is the shell — the
  name, the facts, labels and settings, everything we hold ourselves — rendered at once,
  with the header saying *Reading…* rather than a last-known state that could read as
  current. Where the quick view, apps and record go, a frame loads `live`, and until it answers it
  shows what it is waiting on in the words it is waiting on: `$ vilice status --json`
  and a cursor. When `live` arrives it fills them, and replaces the
  header and facts with the live ones. A box that does not answer the status read is not
  asked for its record and ledger too, so an unreachable box costs one timeout, not
  three. The frame sends its links and forms to the whole page; only the ceremony opens
  in place, and its act button and Cancel leave it for the whole page, so the notice and
  the settled record land where they belong.

  **Deploying straight to a box is a form, then a preview.** The Apps card's `deploy` opens
  *Deploy an app to this box* — stateless, like everything the machine view does: the
  spec goes to the box and is not kept (`BoxDeploy`, `Machines::AppsController`). An
  app whose intention and drift should stay in view is added under Apps instead, and
  the page says so. The form has the common fields in three steps — **What to run**
  (name on the box, image), **Where it answers** (hostnames, port, health), **Settings**
  (environment, written to the record; secrets, whose values are never recorded; a box
  for each secret file the template declares, its contents sent the same way; storage) — and can **start from a template**, a plain GET that fills every field from
  an App Template and its latest version, carrying what the form has no field for
  (release, accessories, processes, stop_first) along untouched. *Paste a spec instead* is the
  escape hatch, closed by default; a pasted spec or whole envelope replaces the fields.
  The form checks only what it must — a box-safe name, an image, well-formed
  `NAME=value` lines — and leaves the rest (the digest pin, port range, volume paths)
  to the box, which refuses at its render boundary. **Preview** sends nothing: it shows
  the plain reading, the record line it will write, the command, and under *Raw spec*
  the exact envelope `vilice deploy` reads — `{ "app": spec, "secret_values": … }` —
  with every secret value masked. The `deploy` button there is the act.

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

  **Machine Settings is its own page** (`/machines/:id/settings`), reached by the
  **Settings** button beside the facts. Ownership, sharing, the key, transfer and
  removal configure the box rather than report on it, so none of it sits in the way of
  the live view ([`machine-settings-is-a-page.md`](../../decisions/machine-settings-is-a-page.md)).
  In order:
  - **Ownership**, as a sentence: *Owned by project Acme.* An unowned box says *No
    project owns this box* and offers **Make owner** right there — giving a box an owner
    takes nothing from anyone.
  - **Who can use it**: three choices — *Owner only*, *Any project*, *Owner and chosen
    projects* — each saved as it is picked. The chosen projects are chips with an ×, and
    an *Add a project…* picker that saves on pick.
  - **Vilice's key**: the authorize line, copyable, with the scope it grants.
  - **Danger zone**, drawn apart in dashed red. **Transfer ownership** is closed until
    opened, and its picker starts on *Choose a project…*, so pressing Transfer without a
    choice cannot release the box; releasing is its own named option (*No project —
    release it*), and the button confirms. **Remove this machine**: with a grant key it
    is the **`revoke`** command button — the console revokes its own key on the box as a
    recorded act, then forgets the box, and a refusal forgets nothing; *Remove without
    revoking* sits beside it for a box that cannot be reached. Below grant scope the
    console cannot revoke itself, so the panel is two numbered steps — the revoke line to
    run on the box, then a **Forget** button named for the only half it does.

  **A box Vilice has never reached leads with its authorize line.** Until the first read
  lands, the box is waiting on one thing — the line run on the box — so a **Connect**
  panel sits above the live view with that line and a `status` button to read the box
  once it is run. It goes away on the first successful read.

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
  (`observe ⊂ operate ⊂ grant`). Read straight off each box through `vilice actors`,
  never from a stored copy — `authorized_keys` *is* the ledger, and a mirror of it here
  would be a second answer to "who can act on this box" that could quietly disagree
  with the box. So the page has no model behind it and nothing to keep in sync.
  **The page never waits on the fleet.** The shell renders at once; the ledgers load
  into a frame (`AccessController#live`) that shows `$ vilice actors --json` and a
  cursor until they arrive. Every box is read in parallel, four at a time
  (`Vilice::Observe.actors_of`), so the page costs about the slowest box rather than
  the sum of them — one unreachable box is one timeout, not one added to everyone
  else's wait. **Re-read** refreshes the same way.

  **One list of keys, grouped — not one card per box.** The row is a *line of a
  ledger* (`AccessLine`), and the same set of lines is read down three axes:

  - **Reach** (the default) — one ordered ladder, most reach first. An ungated line
    is not a rung: a key with no forced command has **no ceiling at all**, which puts
    it *above* `grant` rather than beside it. So the keys Vilice did not write lead
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
  line begins with the key type Vilice reported, because guessing at a position would
  be inventing an owner for the most dangerous row on the page.

  Observe only. Granting and revoking are acts, and they happen where acts happen.
  Re-reading is a **POST**: it opens an SSH connection to every box in the fleet, and
  a GET must be safe to repeat unasked.
- **App Library** — the curated app catalog (the app front-of-funnel — see
  [`journeys.md`](journeys.md)).

  **A release must be digest-pinned.** The box refuses an unpinned image
  (`vilice/internal/app/deploy.go`), so a floating tag in the library is a release
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
4. **Acts** — each in the card it acts on, on a command button. The preview that opens
   there is the violet "this will be recorded" step.

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
when — is the reading. An act that ran a vilice command leads it with a **stamp** of
that command's verb — the button that was pressed, drawn flat (square corners, no hover,
no pointer) so it reads as a record of a press and never as a thing to press. The door
the act came through sets the stamp (`ChainItem#via`): **filled** violet with the mark
when this console sent it; **dashed yellow with a terminal glyph**, tagged *on the box
itself*, when it ran there rather than through a scoped key (Vilice records a local run
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

Beneath the plain line, the **command that ran**, in bold mono: `vilice apply-updates
--json` for an act the console sent (from `Event.raw["command"]`), `vilice deploy app1`
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
backup, restore, apply-updates, route, registry-logout):

1. **Compose** — pick what (image digest, target). Only acts that need it (deploy).
2. **Preview the record entry** — show the exact accountable line before it runs:
   `nick · deploy · acme-web · @sha256:abc → db-1`, rendered with the real chain styling,
   nothing written. The record-before-act invariant *is* the confirm dialog.
3. **Confirm** — the friction. Friction is a feature on the dangerous side.
4. **Settle** — the outcome is stamped on the same entry (`pending → ok/failed`). Rollback
   is a *new witnessed act*, never a silent undo.

Verbs come from an allowlist (`Mutation::ACTS`), never raw input. An app-scoped act names
its app by an `App` we hold or by the name the box reports; a name, a registry host and the
frame the preview opens in are each checked against a fixed pattern before they are used,
because the first two are written into a command. The deploy/rollback path
pipes the desired-state envelope on scoped-SSH **stdin** so secret values never ride the
recorded command line. The settle step reuses the **same timeline component** the observe
side renders — the deploy screen isn't special, it's the record, live. That is how the
record-as-spine model avoids becoming two apps.

**`reached` is not `ok`.** The transport reports the two separately, because "we never
got to the box" and "the box answered and refused" are different failures with different
fixes, and the raw SSH output names neither. `ssh` exits **255** when ssh itself could not
get through; any other non-zero status is the remote command's own, and an unreadable
reply is still a reply. The two streams are read apart: **stdout is the reply**, JSON and
nothing else, and **stderr is the log** — what the box's tools printed, and ssh's own
complaints. A settled entry keeps both, the reply first, so `apply-updates` shows what
apt did.

**A changed host key is named.** ssh refuses a host that answers with a different key
than it remembered — rightly: that is a machine in the middle, and also a rebuilt box.
Its own message is forty lines of capitals, so the console says what happened, points
the innocent case to Machine Settings → *The box's key* — both fingerprints side by side,
and *Trust the new key*, a recorded act — and says the other case exists. The key itself
is pinned on the Machine
([`host-keys-are-pinned-on-the-machine.md`](../../decisions/host-keys-are-pinned-on-the-machine.md)). No "check the box is up" hint is added to it. A failed act that never reached its box has `Machine#connection_hint`
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
> Vilice sub-step protocol; tracked in the open roadmap.

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

- **Theme** — a named set of token values (`Theme::ALL`). `vilice` is the default and
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

The shape above is settled. What is still ahead — ingestion (#6), the generic focus/pin
lens (#10), the rest of secret/env (#14), live-watch (#15), Access's write half (#16), the
chain-integrity badge (#17), the shareable client view (#18), the command palette (#19),
and Vilice Console-deploys-Vilice Console (#20) — is tracked in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). When a screen lands and
settles, its canonical description moves here.
