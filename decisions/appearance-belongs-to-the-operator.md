# Appearance belongs to the operator, and lives in one place

Decided 2026-08-11. The canonical description is in
[`blueprint/console/interface.md`](../blueprint/console/interface.md); this is the *why*.

## The question

The console had a light/dark toggle that wrote `localStorage` and a `[data-theme="dark"]`
block. Three things were wrong with it, and they only became visible when we went to add a
second theme.

**It had drifted from the design system.** [`blueprint/design/tokens.md`](../blueprint/design/tokens.md)
is canonical and says both surfaces declare the same names — *"a value that differs between
the two is a bug in one of them."* The console was running a **different palette
entirely**: an auburn-red accent on light, lime-green with a magenta rail on dark, against
the site's near-black-and-yellow. Not a shade off — a different identity.

**One axis was doing two jobs.** `data-theme` held `light|dark`, so "which theme" and
"which half of it" were the same attribute. A second theme had nowhere to go.

**The browser held the answer.** `localStorage` was the source of truth, applied by a
pre-paint script to avoid a flash. That is a mirror that can disagree with the server —
the exact pattern this project rejects on the Access page, on `authorized_keys`, and on
the machine-view deploy.

## The decision

**Two axes, stored on the `User`, rendered onto `<html>`.**

- `theme` — a named set of token values (`Theme::ALL`). Default `vilice`.
- `mode` — `light`, `dark`, or `system`. Default `system`.

`vilice`'s light half **is** the canonical palette: near-black on near-white, yellow used
graphically. The interactive colour is ink, so links and buttons carry their own contrast
and yellow is left to mark position — the active rail item, the focus halo. That is what
makes black-and-yellow read as clean rather than branded-at, and it is the site's own rule
(`#F2C200` is 1.7:1 on white and may never be text there).

Its dark half is where the palette gets some voltage: neon yellow accent, orange mutate,
neon-green health, a purple rail spark. **Blue stays blue.** Observe means the same thing
in both modes; a mode that re-assigns meaning is a different theme, not a darker one.

**On the `User`, not `Setting`.** `Setting` is fleet policy — one row, applies to everyone.
How the console looks to *you* is not policy, and putting it there would mean one operator
restyling the console for the whole team.

**Not a recorded act.** It touches no box and changes nothing about the fleet, so it stays
off the record, on the same side of the line as observe. The record is for acts.

**One place only.** No `localStorage`. The preference is on the user, so the theme is
already right in the first byte — there is nothing to flash and nothing to disagree. The
one value the server cannot resolve is `system`; a small pre-paint script asks the OS and
turns it into a concrete mode. It *reads* the preference off the element and never writes
one, so it resolves rather than duplicates. This also deleted the dark block that had been
maintained twice — once for the attribute, once for the media query.

## Roads not taken

- **Keep `localStorage`, sync it to the server.** Rejected: two answers, and the sync is
  the bug surface. If the record is authoritative there is nothing for a cache to add
  except a way to be wrong.
- **Put appearance on `Setting`.** Above: it is not fleet policy.
- **Record appearance changes as `Event`s.** Rejected — it would put "changed theme"
  beside "deployed" and "revoked", which cheapens the chain the whole product is about.
  The same reasoning that keeps status samples out ([`a-sample-is-not-an-act.md`](a-sample-is-not-an-act.md)).
- **One axis, with themes named `vilice-light` / `vilice-dark`.** Rejected: it multiplies
  entries by two, makes "follow my system" incoherent, and means a new theme is two
  registry entries that must be kept in step.
- **Rename the console's neutrals to `--paper`/`--ink-soft` in the same change.** Deliberately
  held back so this change was a palette change and nothing else. Tracked in
  [`open/ui-roadmap.md`](open/ui-roadmap.md), with a mapping table in the meantime.
- **A CSS-only theme picker** (`:has()`, a checkbox hack). Rejected: it cannot persist
  across devices, and the preference genuinely belongs to the operator, not the browser.
