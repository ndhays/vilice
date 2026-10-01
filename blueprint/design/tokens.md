# Design — Tokens

> The canonical values. Every surface declares these names in its own `tokens.css`
> (`site/assets/tokens.css`, `console/app/assets/stylesheets/tokens.css`). A value
> that differs between them is a bug in one of them.

**Status:** Canonical. Last touched 2026-08-19.

> **The console uses different *names* for the neutrals, with the same values.** The
> table below is the site's vocabulary; the console's `tokens.css` says `--bg` where
> this says `--paper`, and `--muted` where this says `--ink-soft`. The values were
> converged on 2026-08-11 — before that the console also ran a different *palette*
> (an auburn-red accent on light, lime-and-magenta on dark), which was a plain
> violation of the rule above. The remaining rename is tracked in
> [`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md); until it
> lands, this is the mapping:
>
> | This document | Console |
> |---|---|
> | `--paper` | `--bg` |
> | `--ink-soft` | `--muted` |
> | `--term-bg` / `--term-ink` | `--raw-bg` / `--raw-ink` |
> | `--yellow-deep` | `--accent-text` |
>
> The console additionally carries what the site has no need for: the observe/mutate
> spine, the rail, and the health-dot scale. Those are its own extension, not a
> divergence — see [`blueprint/console/interface.md`](../console/interface.md).

---

## Colour

### Neutrals — light

| Token | Value | Contrast on `--paper` | Job |
|---|---|---|---|
| `--paper` | `#FAFAF8` | — | The page |
| `--card` | `#FFFFFF` | — | A raised surface |
| `--inset` | `#F2F1EE` | — | A recessed one: inline code, a metric |
| `--ink` | `#121212` | 17.9:1 | Body text, headings, links |
| `--ink-soft` | `#565451` | 7.2:1 | Secondary text, table headers, the footer |
| `--ink-faint` | `#6E6B66` | 5.1:1 | Hints. The floor — and it is set by `--inset`, where it is 4.7:1, not by `--paper` |
| `--line` | `#E4E2DD` | — | Hairlines |
| `--line-strong` | `#C9C6BF` | — | A border that has to be seen |

### The accent

| Token | Value | Job |
|---|---|---|
| `--brand-yellow` | `#F2C200` | The one accent. Graphic use only on light surfaces |
| `--brand-yellow-dim` | `#C9A200` | The accent on a white card, where `#F2C200` disappears |
| `--yellow-deep` | `#7A5F00` | 5.8:1 on `--paper`. The only yellow-family colour that may carry text on light |

`--brand-yellow` is `#F2C200` everywhere. It is **1.7:1 on white** and therefore
never text, never a link, never an icon that has to be understood. It is allowed
as: the switch in the mark, the active-nav bar, a rule, the halo on a focus ring, a
`::marker`, and any fill whose meaning is already carried by an adjacent label.

### The terminal surface

| Token | Value | Contrast on `--term-bg` | Job |
|---|---|---|---|
| `--term-bg` | `#121212` | — | Command blocks, code blocks |
| `--term-ink` | `#E8E6E1` | 15.0:1 | The output itself |
| `--term-muted` | `#9A968E` | 6.4:1 | A comment, a dimmed continuation |
| `--term-yellow` | `#F2C200` | 11.1:1 | Prompts, flags, the line you type. Text-safe here |
| `--term-line` | `#2C2A28` | — | The frame's inner hairline |

This is where the black/yellow reads, and the only place yellow is allowed to be
text.

### Status

| Token | Value | Job |
|---|---|---|
| `--ok` | `#146B34` | 6.3:1 on `--paper` |
| `--warn` | `#8A5A00` | 5.7:1 on `--paper` |
| `--bad` | `#A81E14` | 7.0:1 on `--paper` |

Status colour is never the only signal — it accompanies a word or a shape.

Every ratio in these tables is measured, not estimated. `--ink-faint` is the one
that needed moving: at `#77746F` it was 4.45:1 on `--paper` and 4.12:1 on `--inset`,
which is below AA for the small uppercase labels it is used for.

---

## Type

Two working families, plus two display faces for one place — all Open Font License, all
self-hosted. No webfont is load-bearing:
every stack ends in a system fallback, and the page is readable before the fonts
arrive (`font-display: swap`).

| Token | Stack |
|---|---|
| `--font-sans` | `"IBM Plex Sans", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` |
| `--font-mono` | `"IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` |
| `--font-display` | `"Bodoni Moda", "Didot", "Bodoni 72", Georgia, serif` — the docs home page title only |
| `--font-inscription` | `"Cinzel", "Trajan Pro", Georgia, serif` — the lines under that title, and the headings of the Horace page |

**IBM Plex Mono is the code face** — it is the one the project already reads code
in. IBM Plex Sans is its sibling: same designer, same skeleton, so the two sit
together without argument.

**The display faces are for the home page's hero, and the page it links to.** The name
in **Bodoni Moda** (after Giambattista Bodoni, Parma, 1798); beneath it in **Cinzel**
(Roman inscriptional capitals) the tagline, then the motto — the letter's first line,
quieter in `--ink-faint` and a step smaller, linking to the whole poem (`/horace.html`,
Latin beside Conington's public-domain English, whose two headings are Cinzel too).
Italian for the name, Horace's Rome for the steward it comes from
([`decisions/the-name-is-vilice.md`](../../decisions/the-name-is-vilice.md)). One weight
each — Bodoni 600, Cinzel 400. Every other heading, the header wordmark, and
the console stay Plex: a display face used everywhere stops being a display face.

Weights: **400** and **600**, and nothing else. Two weights is enough to build a
hierarchy, and every extra weight is another file on the wire.

### Scale

16px base, 1.65 line-height on body text.

| Token | Size | Job |
|---|---|---|
| `--text-xs` | `0.75rem` | Badges, the eyebrow above a heading |
| `--text-sm` | `0.875rem` | Table cells, the footer, nav |
| `--text-base` | `1rem` | Body |
| `--text-lg` | `1.125rem` | h3, the lead paragraph |
| `--text-xl` | `1.375rem` | h2 |
| `--text-2xl` | `2rem` | h1 |
| `--text-code` | `0.8125rem` | Everything in a terminal or code block |

`--text-code` is set by arithmetic, not taste. A help page is written to 78
columns (`core.HelpWidth`); IBM Plex Mono advances 0.6em per character, so 78
columns need `78 × 0.6 × 13px ≈ 608px` — inside the 800px content column with room
for padding. Change one and check the other.

Headings are 600 weight, `line-height: 1.25`, `letter-spacing: -0.015em`. Body is
400. Nothing is set in ALL CAPS except a table header, at `--text-xs` with
`0.04em` tracking.

---

## Space

A 4px base. Use the scale; do not invent values between its steps.

| Token | Value |
|---|---|
| `--space-1` | `0.25rem` |
| `--space-2` | `0.5rem` |
| `--space-3` | `0.75rem` |
| `--space-4` | `1rem` |
| `--space-6` | `1.5rem` |
| `--space-8` | `2rem` |
| `--space-12` | `3rem` |
| `--space-16` | `4rem` |

**Three of those steps also carry a name**, because a form's clarity is in the *ordering*
of its gaps rather than their sizes, and a rule reading `var(--space-3)` says nothing
about which of the three jobs it is doing:

| Token | Is | Job |
|---|---|---|
| `--tight` | `--space-2` | A label to the thing it labels; a note to its neighbour. |
| `--gap` | `--space-3` | Two things inside one step. |
| `--step` | `--space-6` | One step to the next. |

They are **names on the scale, never new values** — the rule above still holds. The order
is the whole point: when a within-step gap drifts up to the size of a between-step gap,
steps stop reading as steps and the page becomes one long column of fields. See the form
pattern in [`../console/interface.md`](../console/interface.md).

---

## Shape

| Token | Value | Job |
|---|---|---|
| `--radius-sm` | `4px` | Inline code, a badge |
| `--radius` | `8px` | Code blocks, cards, buttons |
| `--radius-lg` | `12px` | The terminal frame |

No shadows. Depth is a hairline (`--line`) or a change of surface, never a blur.

---

## Layout

| Token | Value | Job |
|---|---|---|
| `--measure` | `42rem` | The comfortable reading width for prose |
| `--content` | `50rem` | The content column |
| `--sidebar` | `15rem` | The command sidebar |
| `--page` | `76rem` | Content plus sidebar plus gutters |

Below `900px` the sidebar collapses (see `patterns.md`). Below `640px` the page is
one column at `--space-4` gutters.

---

## Focus

One ring, everywhere, on every focusable thing:

```css
outline: 2px solid var(--ink);
outline-offset: 2px;
box-shadow: 0 0 0 6px rgba(242, 194, 0, 0.55);
```

The dark ring does the contrast work — 17:1 against any surface in this system, so
it satisfies WCAG 2.2 non-text contrast on its own. The yellow band outside it is
the accent, and carries no meaning it needs to be legible for. On the terminal
surface the ring inverts: `outline-color: var(--term-ink)`.

`:focus-visible`, not `:focus` — a mouse click should not draw a ring.

---

## Motion

150ms, `ease`, on colour and opacity only. No transforms, no easing curves with
personality, and nothing that moves layout. Everything is wrapped in:

```css
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
```
