# The rail shows the layering

> Decided 2026-08-11. Spec:
> [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## The problem

[`console-layers.md`](console-layers.md) established three rings. The rail stayed a flat
list of eight identical items — `Status · Projects · Machines · Apps · Record · Access ·
App Library · Settings` — three kinds of thing shown as peers, with the rings
outermost-first: Projects above Machines, the floor.

## The decision

**Three bands, divided by a hairline, rings floor-first.**

```
Status · Record                      the spine
Machines · Apps · Projects           the rings, floor first
Access · App Library · Settings      the surfaces that serve them
```

## Roads not taken

- **Make Record the home page**, with the rings as filters. The purest reading of the
  record as spine. Deferred: it changes every entry path, and Status earns the slot by
  leading with exceptions. Revisit after ingestion (#6).
- **Labelled bands** ("The record", "The fleet"). Invents vocabulary to explain a layout.
- **Spacing with no rule.** Reads as a margin bug.
- **Bands in the old order.** Groups the rings while still listing them outermost-first.
- **Collapsible sections.** Eight destinations need no disclosure.
