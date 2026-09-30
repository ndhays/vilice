# Design — Overview

> The canonical picture of how Steward's surfaces look and why. Start here, then
> `tokens.md` for the values, `logo.md` for the mark, `patterns.md` for the parts.

**Status:** Canonical. Last touched 2026-08-09.

---

## What this is

One design system, answered to by two surfaces:

- **The documentation site** (`site/`) — a static Web Origami build.
- **Steward Console** (`console/`) — a Rails app.

They share a foundation: the same mark, the same two typefaces, the same neutrals,
the same yellow, the same focus ring. A reader who moves between them should feel
one project, not two that happen to be adjacent.

They do not share a stylesheet. The token *names and values* are canonical here in
`tokens.md`; each surface declares them in its own `tokens.css`. Wiring one file
through both a Rails asset pipeline and an Origami build is real plumbing for sixty
variables and two consumers — a prose spec plus two mirrors is the boring answer.
If a third surface appears, extract the file then.

---

## What it is for

Steward's whole argument is that you can check it by eye: a small ceiling, a legible
ledger, a record you can `cat`. A design that asks to be admired argues against
that. So the target is a page that gets out of the way — legible, quiet, obviously
unfashionable, and still there in five years.

Concretely, five rules:

1. **Legibility beats identity.** If a choice makes the page prettier and harder to
   read, it loses. Body text is dark on light at a comfortable measure, always.
2. **One accent, used sparingly.** Yellow marks the one thing that matters on a
   screen, and nothing else. Two accents means neither is a signal.
3. **The terminal is a surface, not a decoration.** Command output is shown as
   command output — near-black, monospace, the real bytes. It is not restyled,
   re-typeset, or paraphrased.
4. **Nothing that needs JavaScript to be readable.** Scripts add the copy button and
   the theme toggle. Remove them and every page still works.
5. **Boring on purpose.** No gradients, no shadows beyond a hairline, no animation
   past a 150ms state change, no webfont the page cannot live without.

Tone in copy follows the same line, and is set out in `site/README.md` and
`CLAUDE.md`: plain words, short ones where they will do, true or absent.

---

## Black and yellow, honestly

The accent is Linux yellow on near-black — the palette of the terminal Steward
lives in. It comes with one hard constraint, and the system is shaped around it:

**`#F2C200` is 1.7:1 on white.** It fails every contrast threshold there is. So:

- On light surfaces, yellow is a **graphic accent only** — the switch in the mark,
  the active-nav bar, a rule, the halo on a focus ring. Never text. Never a link.
- On the near-black terminal surface, yellow is **11.1:1**, and there it does carry
  text: prompts, flags, the parts of a help page worth finding.

So the black/yellow signature lives where it is both accurate and accessible: in the
command blocks, which is exactly where a reader's eye is going anyway.

---

## What is shared and what is not

**Shared** (this folder is the source): the mark, IBM Plex Sans and IBM Plex Mono,
the neutral ramp, `--brand-yellow`, the terminal surface, radii, spacing, the focus
ring.

**The console's own** (specified in `blueprint/console/patterns.md`): the
observe/mutate spine — the calm blue of a read, the witnessed violet of a write, the
health dots, the sidebar rail. That vocabulary exists to make one thing visible on
screen: that reading the record and acting on the box are different acts. The docs
site has no acts to distinguish, so it does not carry it.

**The docs site's own** (specified in `patterns.md`): the command page, the terminal
block, the command sidebar.

A surface may extend the foundation. It may not quietly redefine it — a
`--brand-yellow` that differs between the two is a bug in one of them.

---

## Where this came from

The docs site previously carried a warm paper palette with an auburn rail, and the
console an admin red with a near-black sidebar. Neither was written down, so neither
could be checked. This folder exists so a change to either surface has somewhere to
be true.
