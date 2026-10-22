# Appearance belongs to the operator, and lives in one place

> Decided 2026-08-11. Spec:
> [`blueprint/console/interface.md`](../blueprint/console/interface.md).

## What was wrong

The console had a light/dark toggle in `localStorage`.

- **It had drifted from the design system.** The console ran a different palette from the
  one [`blueprint/design/tokens.md`](../blueprint/design/tokens.md) declares for both
  surfaces.
- **One axis did two jobs.** `data-theme` held `light|dark`, so a second theme had nowhere
  to go.
- **The browser held the answer** — a mirror that can disagree with the server, the
  pattern this project rejects elsewhere.

## The decision

**Two axes, stored on the `User`, rendered onto `<html>`.**

- `theme` — a named set of token values (`Theme::ALL`). Default `vilice`.
- `mode` — `light`, `dark`, or `system`. Default `system`.

`vilice`'s light half is the canonical palette: near-black on near-white, yellow used
graphically. The interactive colour is ink; yellow marks position (the active rail item,
the focus halo) and is never text (`#F2C200` is 1.7:1 on white). The dark half has a neon
yellow accent, orange mutate, neon-green health, a purple rail spark. **Blue stays blue:**
observe means the same thing in both modes.

- **On the `User`, not `Setting`.** `Setting` is fleet policy; how the console looks to
  you is not.
- **Not a recorded act.** It touches no box. The record is for acts.
- **One place only.** No `localStorage`, so the first byte is already right. The one value
  the server cannot resolve is `system`; a small pre-paint script asks the OS. It reads the
  preference off the element and never writes one.

## Roads not taken

- **Keep `localStorage`, sync it to the server.** Two answers, and the sync is the bug
  surface.
- **Put appearance on `Setting`.** One operator would restyle the console for everyone.
- **Record appearance changes as `Event`s.** "Changed theme" beside "deployed" cheapens
  the chain ([`a-sample-is-not-an-act.md`](a-sample-is-not-an-act.md)).
- **One axis, with themes named `vilice-light` / `vilice-dark`.** Doubles the entries and
  makes "follow my system" incoherent.
- **Rename the console's neutrals to `--paper`/`--ink-soft` in the same change.** Held
  back so the change was a palette change only. Tracked in
  [`open/ui-roadmap.md`](open/ui-roadmap.md).
- **A CSS-only theme picker** (`:has()`, a checkbox hack). Cannot persist across devices.
