# Group the fleet, don't filter it — and offer tenancy rather than assume it

> Decided 2026-08-11. Spec:
> [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The decision

**Grouping is the primitive on the Machines list.** `MachineGroups` declares the ways the
fleet can be arranged. The old *Unowned* filter answered one question by hiding every
other box; `group=owner` answers it and shows the owned boxes too, with counts.

- Each grouping is a **URL** (`?group=status`), as the Record's filters are.
- Groups lead with what needs a look: unreachable before reachable, "No owner" before any
  named client.

### Owner is offered, not assumed

`owner` is a `Project` — one ring out ([`console-layers.md`](console-layers.md)). It is
one choice in a menu, not a column in the row. **The test:** with tenancy never mounted,
this page loses one menu item and nothing else moves. A test asserts `owner` is the only
grouping marked `tenancy`.

### The headline

Each list page states its story in one line — `14 boxes · 2 unreachable · 3 not yet
seen`. **A headline may state only facts its own ring owns.**

## Roads not taken

- **Keep the Unowned filter alongside grouping.** Two primitives for one question, and
  the filter is the weaker.
- **Animate the rearrange.** `blueprint/design/tokens.md` allows motion on colour and
  opacity only. The list fades, 150ms. A spinner padded to a fixed time was also rejected:
  showing progress for work that is not happening is a lie.
- **Group client-side.** The view would not be shareable.
- **A generic "group by any column" builder.** A grouping needs its own ordering rule
  (exceptions first), and an enumerated list is what the tenancy test asserts against.

## Still open

**Grouping by role** — the most natural one — is blocked: `role` comes from a live
`vilice status` read and is not persisted, and drawing a list must not cost N SSH round
trips. It arrives with ingestion (#6 in [`open/ui-roadmap.md`](open/ui-roadmap.md)).
