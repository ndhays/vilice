# Design — Patterns

> The parts both surfaces build from, and the docs site's own. Values come from
> `tokens.md`; nothing here restates a hex code.

**Status:** Canonical. Last touched 2026-08-11.

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

One page per command, and its top is the literal output of `vilice <name> --help`.
Not a description of it, not a table derived from it: the bytes, from the binary,
captured at build time by `vilice _commands`. If the page and the terminal ever
disagree, the site is wrong, and it cannot be — there is only one renderer.

The shape:

1. **`vilice <name>`** as the `h1`, in `--font-mono`.
2. The summary line as a lead paragraph, `--text-lg`, `--ink-soft`.
3. Two badges: the scope, and whether the command is recorded. The scope badge
   carries the yellow bar; recorded/not-recorded is a word, not a colour.
4. **The terminal block** with the whole help page, headed `vilice <name> --help`
   in a title bar so a reader knows what they are looking at.
5. Any hand-written prose, under `## Notes`. Most commands have none — that is the
   point. Prose here is for what the help page genuinely cannot hold: a caveat, a
   pointer at a decision record, a link to a related command.

A command page that needs a lot of prose is a help page that needs improving. Fix
the CLI first.

---

## The command index

`/commands/` lists every command, sectioned, grouped and ordered exactly as
`vilice help` does — both levels come from the same `core.Groups`, so the site
cannot invent a taxonomy the binary does not have. Each row is the name in mono and
the summary in sans. Nothing else; the detail is one click away.

**Two levels, two questions.** The **section** answers *who runs this* — root, the
_vilice user, systemd — and is the coarser thing a reader arrives with. The
**group** answers *how far it reaches*. A section is `h2`, upper-cased and quiet in
`--ink-faint`, labelling a run of groups rather than competing with them; a group is
`h3` in ordinary weight. Sections upper-case in CSS, never in the stored string, so
the same list can head a man page and a terminal without being shouted twice.

---

## The sidebar

Present only under `/commands/`. A sticky column, `--sidebar` wide, listing every
command by section and then by group. The group is indented under its section and
set lighter, because two levels a reader cannot tell apart at a glance are worth
less than one. The current page is marked by weight plus a `--brand-yellow` bar in
the left gutter — never colour alone, because the bar is graphic and the weight is
the accessible signal.

Below `900px` it collapses into a `<details>` disclosure above the content,
labelled "All commands". A disclosure, not a drawer: it works without JavaScript,
it is one element, and it has nothing to get stuck open.

---

## The home page

The one page whose job is the hook rather than the reference. It is five parts and
nothing else, and each of them appears only here.

**The hero.** `h1` at `clamp(2.5rem, 9vw, 4rem)` — the one element on the site
sized against the viewport rather than a token, because it is the one element that
should fill the screen it lands on. Under it a short `--brand-yellow` rule (graphic
use, carrying no meaning), then the tagline at `--text-lg`+ in `--ink-soft`, capped
at `--measure`.

**The split.** A two-column card, figure on the left and the command you would
actually type on the right, `1fr / 3fr` so the command has the room. It stacks below
`640px`, figure first. The figure is the mark as line art on `currentColor`, so it
takes the page's ink and there is no second copy of the asset in another colour.

Under the mark sits the **version badge**: the terminal surface shrunk to a pill,
`--term-bg` with the number in `--font-mono` and `--term-yellow` — the one accent
that is contrast-safe as text, and it lives here for the same reason the terminal
block does. The label *Current version* sits above the number rather than beside it,
both centred: the figure column is 180px at the page's full width, and the two set on
one line measure 204px — they overhang the card. Stacked they are 145px, and the
label is still a word, so no meaning is carried by colour alone. It reads as a
caption on the mark, which is what a version is. Both the badge and the
install command beside it are filled
from `VERSION` at build time (`{{version}}`, replaced by `site/versions.js`); a docs page
claiming a release that is not the current one is a failure mode worth removing
rather than remembering.

**The tool list.** Other people's projects, one per row on a hairline. Each line is
the name and a plain sentence saying what the tool is *for* — never how it compares
to Vilice. A comparison table would be a claim about software we do not maintain.

Indented one step (`--space-6`, and `--space-4` below `640px`), so the run of rows
reads as a block belonging to the sentence above it rather than as more prose at the
same left edge. The indent is padding inside `--measure`, so the block still ends
where the paragraphs do: inset, not pushed out.

The page uses it twice, and the same rule holds both times: once for what Vilice
**stands on** (*Dependencies* — OpenSSH, systemd, Podman, Caddy, restic, and the
hardening tools), and once for what a reader might **choose instead**
(*Inspiration*). Each run gets its own `h3` **and a tagline**, so the two lists are
told apart at a glance rather than by inferring it from a lead-in sentence — the
heading is one word, and the tagline carries the qualifier the heading would
otherwise have to swallow. Naming the substrate is not a disclaimer — a tool that
hides what it drives is asking to be trusted rather than checked, and every one of
these writes its own plain config that outlives us.

**The provisional card.** `--inset` fill inside a 2px dashed `--line-strong`
border. Dashed because that is how scaffolding has read since long before the web,
and the card's own heading says the same thing in words — the shape and the words
both carry it, never the border alone. It is for what is true now and meant to stop
being true; today, that Vilice is a proof of concept. **When the thing it describes
is no longer provisional, the card goes** — this pattern has no settled variant, on
purpose.

---

## Roles

On the overview page, the two roles a box can be prepared as are a card each, side
by side and collapsing to one column: a line-art icon on `currentColor`, the role
name as an `h3` in `--font-mono` (it is a word you type), one sentence of what it is
for, and the command that prepares it.

Two cards, not a table: the set is closed at two, and a reader should be able to see
both and choose. A third role would be a code change in the binary before it was a
change here — the page cannot show one the binary does not have.

---

## Page chrome

**Header.** The lockup on the left, primary nav on the right: Home, Overview,
Commands, Console, App Library, Source. Home is named rather than left to the mark — a lockup is
a convention, and a reader who does not know it should not have to guess. Nav items
are `--text-sm`, `--ink-soft`, and go `--ink` on hover with a `--brand-yellow`
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

**Taglines.** A heading may take a `.tagline` under it: the heading names the section
in as few words as possible, the tagline says it in a few more. Always `--ink-soft`,
always hugging its heading — the heading's own bottom margin is the gap, so no
negative margin holds the pair together — and always **scaled to that heading**:
`--text-sm` under a section `h3`, `--text-xl` under the hero's `h1`. The pair earns
its place when the honest single-line heading would be a heading with a conjunction
in it; when the heading stands alone, it stands alone.

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
