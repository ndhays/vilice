# Design — Patterns

> The parts both surfaces build from, and the docs site's own. Values come from
> `tokens.md`; nothing here restates a hex code.

**Status:** Canonical. Last touched 2026-08-09.

---

## The terminal block

The signature component. It shows command output as command output: `--term-bg`,
`--font-mono` at `--text-code`, `--radius-lg`, no syntax highlighting.

It scrolls **inside its own frame** (`overflow-x: auto`), so a line too long for a
phone never makes the page scroll sideways. Help pages are written to 78 columns so
this rarely fires (see `tokens.md`, *Scale*), but `route`'s JSON and a long image
digest will.

Every block gets the copy button (`site/assets/copy.js`): a real `<button>`, an
`aria-label`, an `aria-hidden` icon, and a shared live region that announces the
result. It appears on hover and on keyboard focus, and stays faintly visible where
there is no hover.

Three uses, one component:

- **A command to run.** What the reader types. This is the common case.
- **`--help` output.** On a command page, framed and labelled — see below.
- **A file's contents.** A spec, a routing table, an `authorized_keys` line.

---

## The command page

One page per command, and its top is the literal output of `steward <name> --help`.
Not a description of it, not a table derived from it: the bytes, from the binary,
captured at build time by `steward _commands`. If the page and the terminal ever
disagree, the site is wrong, and it cannot be — there is only one renderer.

The shape:

1. **`steward <name>`** as the `h1`, in `--font-mono`.
2. The summary line as a lead paragraph, `--text-lg`, `--ink-soft`.
3. Two badges: the scope, and whether the command is recorded. The scope badge
   carries the yellow bar; recorded/not-recorded is a word, not a colour.
4. **The terminal block** with the whole help page, headed `steward <name> --help`
   in a title bar so a reader knows what they are looking at.
5. Any hand-written prose, under `## Notes`. Most commands have none — that is the
   point. Prose here is for what the help page genuinely cannot hold: a caveat, a
   pointer at a decision record, a link to a related command.

A command page that needs a lot of prose is a help page that needs improving. Fix
the CLI first.

---

## The command index

`/commands/` lists every command, grouped and ordered exactly as `steward help`
groups and orders them — the same `core.Groups`, so the site cannot invent a
taxonomy the binary does not have. Each row is the name in mono and the summary in
sans. Nothing else; the detail is one click away.

---

## The sidebar

Present only under `/commands/`. A sticky column, `--sidebar` wide, listing every
command by group. The current page is marked by weight plus a `--brand-yellow` bar
in the left gutter — never colour alone, because the bar is graphic and the weight
is the accessible signal.

Below `900px` it collapses into a `<details>` disclosure above the content,
labelled "All commands". A disclosure, not a drawer: it works without JavaScript,
it is one element, and it has nothing to get stuck open.

---

## Page chrome

**Header.** The lockup on the left, primary nav on the right. Nav items are
`--text-sm`, `--ink-soft`, and go `--ink` on hover with a `--brand-yellow`
underline. One hairline under the whole thing.

**Banner.** Full width, above the header, for a notice that must not be missed —
today, that the project is a proof of concept. `--term-bg` with `--term-yellow`
text: the one place the accent shouts, and it is contrast-safe there.

**Footer.** Version, licences, source. `--text-sm`, `--ink-soft`, one hairline
above.

**Skip link.** First focusable element on every page, hidden until focused.

---

## Prose

Body copy is capped at `--measure`, not `--content` — a 50rem line of 16px text is
too long to track. Tables and terminal blocks may use the full `--content` width.

Headings: `h2` takes a hairline above it and generous space; `h3` does not. Both
carry an automatic anchor id (the site slugifies the heading text). Long pages open
with a contents line of `·`-separated anchor links.

Links in prose are `--ink` with a `--brand-yellow` underline at `0.15em` offset,
thickening on hover. The text does the contrast work; the yellow is the accent.
This is the one place yellow appears in a run of text, and it is decoration — a
reader who cannot see it still sees an underline.

Inline code is `--font-mono` at `0.875em` on `--inset`, `--radius-sm`.

Blockquotes carry a 3px `--brand-yellow` left border and `--inset` fill, square
corners on the bordered side.

Tables: hairline row separators, no vertical rules, no zebra. The header row is
`--text-xs`, uppercase, `--ink-soft`.

---

## What both surfaces owe

- Every interactive element takes the focus ring from `tokens.md`, unmodified.
- Nothing conveys meaning by colour alone (WCAG 1.4.1): a colour always accompanies
  a word, an underline, a shape, or a position.
- Every page works with JavaScript off. Scripts add the copy button and the
  console's theme toggle; neither is load-bearing.
- Every image and icon is either decorative and `aria-hidden`, or labelled.
- Touch targets are at least 24×24px, and 44×44px where there is room.
