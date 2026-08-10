# Design — Tokens

> The canonical values. Every surface declares these names in its own `tokens.css`
> (`site/assets/tokens.css`, `console/app/assets/stylesheets/tokens.css`). A value
> that differs between them is a bug in one of them.

**Status:** Canonical. Last touched 2026-08-09.

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

Two families, both Open Font License, both self-hosted. No webfont is load-bearing:
every stack ends in a system fallback, and the page is readable before the fonts
arrive (`font-display: swap`).

| Token | Stack |
|---|---|
| `--font-sans` | `"IBM Plex Sans", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` |
| `--font-mono` | `"IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace` |

**IBM Plex Mono is the code face** — it is the one the project already reads code
in. IBM Plex Sans is its sibling: same designer, same skeleton, so the two sit
together without argument.

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
