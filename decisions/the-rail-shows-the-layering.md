# The rail shows the layering

Decided 2026-08-11. The resulting nav is canonical in
[`blueprint/console/interface.md`](../blueprint/console/interface.md); this is the *why*.

## The question

[`ui-shape.md`](ui-shape.md) rejected **Shape A** — the refined admin panel inherited from
`switchyard-platform` — as the spine, keeping it only as something to steal polish from.
[`console-layers.md`](console-layers.md) then established three rings, each optional above
the one below.

Neither reached the rail. It stayed a flat sidebar of **eight visually identical items**:

```
Status · Projects · Machines · Apps · Record · Access · App Library · Settings
```

Two things were wrong with that. The items are three different *kinds* of thing — chain
lenses, rings, and cross-cutting surfaces — rendered as peers. And the rings ran
**outermost-first**: Projects, the most optional ring, sat above Machines, the floor.

The layering work was real, but it landed in the models and routes — `App.project` made
optional, apps given their own home — and its entire visual footprint was *one extra nav
item*. So the architecture said three rings and the rail said admin panel. That drift is
what makes someone look at a shipped console and see the old product.

[`interface.md`](../blueprint/console/interface.md) also claimed "Apps sits between
Machines and the rest **on purpose**" — a purpose no reader could see, because nothing
distinguished it from its neighbours.

## The decision

**Three bands, divided by a hairline, rings bottom-up.**

```
Status · Record                      the spine
Machines · Apps · Projects           the rings, floor first
Access · App Library · Settings      the surfaces that serve them
```

The floor comes first and tenancy comes last, so the rail reads in the order the rings are
actually built — and the "Apps sits between" claim becomes visibly true rather than
merely asserted.

## Roads not taken

- **Spine-first: make Record the home page**, with the rings as filters over it. The purest
  reading of Shape B — if the record is the spine, the chain should be the landing page.
  Deferred, not rejected: it is a large change to every entry path, and Status already earns
  the slot by leading with exceptions ("calm by default" is the *other* half of the design,
  and a raw chain is not calm). Worth revisiting after ingestion (#6) makes the fleet-wide
  chain complete enough to land on. Until then, Status is the head of the record, which is
  the model the docs already use.
- **Labelled bands** ("The record", "The fleet"). Rejected: it puts words in a rail that has
  none, and names the groups something the rest of the docs never call them — inventing
  vocabulary to explain a layout, which the naming rule in `CLAUDE.md` treats as the layout
  having failed. A hairline is enough.
- **Spacing with no rule.** Rejected as too quiet to read as deliberate; it looks like a
  margin bug.
- **Keeping the current order and only adding bands.** Rejected: it would group the rings
  correctly while still listing them outermost-first, which is the more misleading half.
- **Collapsible sections / an accordion rail.** Rejected — eight destinations do not need
  progressive disclosure, and hiding a destination behind a click to tidy a rail that fits
  on screen trades legibility for neatness.
