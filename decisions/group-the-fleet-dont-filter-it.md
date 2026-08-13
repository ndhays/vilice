# Group the fleet, don't filter it — and offer tenancy rather than assume it

Decided 2026-08-11. The resulting page is canonical in
[`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The question

The Machines list had a search box and one filter chip: **Unowned**, which narrowed the
list to boxes with no owner. It answered a real question — *which boxes have no home* —
but only by hiding every box that did.

That is the wrong primitive for this page. Machines is the **floor** of the three rings
([`console-layers.md`](console-layers.md)), and what an operator asks it is *what is the
shape of my fleet*: how many boxes are unreachable, how many have never been seen, which
are behind the edge, which are unclaimed. A filter answers one of those at a time. A
grouping answers all of them at once, with the counts, in one look.

## The decision

**Grouping is the primitive.** `MachineGroups` declares the ways the fleet can be
arranged; the Unowned filter is gone, because it was one grouping wearing a filter's
clothes and `group=owner` says it better — and shows the owned boxes too.

Each grouping is a **URL** (`?group=status`), so a grouped view can be shared or
bookmarked. That is the rule the Record destination already follows for its filters, and
there is no reason for this page to invent a second one.

Groups lead with **what needs a look**: unreachable before reachable, "No owner" before
any named client. The page's calm-by-default posture survives the rearranging.

### Owner is offered, not assumed

`owner` is a `Project` — one ring out. It stays on the page because *which boxes have no
home* is a real operational question with no better home today, but it is **one choice in
a menu** rather than a column in the row.

That is the test the floor has to pass: **with tenancy never mounted, this page loses one
item from a menu and nothing else moves.** A column would have left a hole; a grouping
leaves a shorter list of groupings. It is the same shape the eventual
`steward-projects` engine needs, bought early and cheaply.

Nothing else on the page reaches out of layer 1 — no install counts, no project health.
A test asserts that `owner` is the *only* grouping marked `tenancy`, so the next one
added has to be deliberate.

### The headline

Each list page states its own story in one line — `14 boxes · 2 unreachable · 3 not yet
seen` — generalising what the Status page already did with `All clear · 1 install · 1
machine`. The rule that keeps it honest: **a headline may state only facts its own ring
owns.** The moment the Machines headline says "3 installs failing", the floor has reached
up a ring again.

## What this does not settle

**Grouping by role** is the most natural way to group a fleet, and the purest layer-1
fact there is — the box says what it is for. It is not here, because `role` is not
persisted: it comes from a live `steward status` read, the fleet list does no per-machine
read, and drawing a list must never cost N SSH round trips. It arrives with ingestion
(#6). Worth noting the irony — the one grouping that is *purely* the floor's own is the
one blocked, while the one that reaches out of the ring was the easy one.

## Roads not taken

- **Keep the Unowned filter alongside grouping.** Rejected: two primitives for one
  question, and the filter is strictly the weaker of the two.
- **Animate the rearrange.** Rejected as specified: `blueprint/design/tokens.md` says
  motion is "on colour and opacity only… nothing that moves layout", and a regroup that
  slides rows is exactly that. The list instead **fades**, 150ms, opacity only — which the
  rule already permits, so no amendment was needed. A spinner padded to a fixed duration
  was also rejected: regrouping is cheap, and showing progress for work that is not
  happening is the same lie as a canned `ok` for an act that never ran
  ([`a-sample-is-not-an-act.md`](a-sample-is-not-an-act.md)).
- **Group by owner client-side.** Rejected: the view would not be shareable, and the
  server already has the rows.
- **A generic "group by any column" builder.** Rejected as premature — an enumerated list
  is legible, is what the tenancy test can assert against, and a grouping usually needs
  its own ordering rule (exceptions first) that a generic builder would not know.
