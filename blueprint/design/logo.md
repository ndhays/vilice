# Design — The Mark

> Files: `site/assets/logo.svg`, `site/assets/favicon.svg`,
> `site/assets/logo.png`, `console/app/assets/images/logo.svg`.
> In the console the mark is inlined — one partial, `app/views/shared/_mark.html.erb`,
> rendered by the rail and by the auth lockup. It takes a `size:` and nothing else,
> so there is no second hand-drawn copy to drift.

**Status:** Canonical. Last touched 2026-08-09.

---

## What it shows

A box, drawn as a terminal window. Two solid arrows arrive from opposite sides and
converge on a single yellow point at its centre. Below them, a prompt row: two dots
and a caret line, waiting.

It is the system's one sentence, drawn: **many callers, one door.** The console, a
CI job, and a person at a shell all arrive from different directions and all pass
through the same point — and the point is lit, because that is where the record is
written. The prompt row says what kind of thing this is: a terminal, waiting for a
named command, not a dashboard.

The mark is not clever and does not need decoding. That is the requirement, not a
shortfall.

---

## Construction

A 24-unit square. Strokes are `1.5`, round-capped and round-joined; the arrows and
dots are solid fills.

| Part | Geometry |
|---|---|
| The box | `rect` 2,4.5 → 22,19.5, `rx` 2.5 |
| Left caller | triangle 6.4,7.5 → 6.4,13.1 → 10.5,10.3 |
| Right caller | triangle 17.6,7.5 → 17.6,13.1 → 13.5,10.3 |
| The door | circle 12,10.3 `r` 1.5, `#F2C200` |
| Prompt | circles 6,16.8 (`#F2C200`) and 8.7,16.8, `r` 0.9; line 11.8 → 18 |

**Everything black is `currentColor`.** The mark inherits the ink of whatever it
sits in, so one file serves the light header, the dark console rail, and a footer at
50% opacity. Only the yellow is literal `#F2C200` — it is the accent, and it does
not follow the text.

---

## Two files, on purpose

`logo.svg` is the mark as drawn. It is legible down to about **24px**.

`favicon.svg` is a reduction for tab size. At 16px the two prompt dots are under a
pixel across and the 1.5-unit box stroke blurs into the arrows: the whole thing
becomes a grey smudge. So the favicon drops the prompt row and the hairline box, and
puts the surviving silhouette — two arrows converging on the yellow point — on a
solid `#121212` tile with `rx` 5. The arrows go `#FAFAF8` so the tile reads on light
and dark browser chrome alike.

They are the same mark. One of them has been told the truth about 16 pixels.

Use `logo.svg` at 24px and above; `favicon.svg` for the tab and anywhere the mark
appears smaller than 24px or on a busy background.

`logo.png` is a raster of the mark, and exists for the two places that cannot take
an SVG: `og:image`, which every social platform rasterises anyway, and the
`apple-touch-icon`. It is not for use in a page.

---

## The lockup

Mark, then a `--space-2` gap, then **`vilice` in IBM Plex Mono 600, lowercase**,
optically aligned to the box's centre line rather than its bounding box. Lowercase
because that is how you type it.

A yellow block cursor may follow the wordmark — a filled rectangle roughly `0.42em`
wide by the cap height — where the lockup has room to be the page's identity: the
site header, the README, an `og:image`. Leave it off in tight chrome. It never
blinks; an animated cursor in a header is a distraction with no information in it.

The wordmark is `vilice` alone — and it is now the *only* lockup. The console used
to set "Vilice Console" as the mark plus the words in `--font-sans`; it dropped the
second word, so the rail and the sign-in card wear this one. "Vilice Console" names
the Rails app, and appears nowhere in the UI
([`blueprint/console/interface.md`](../console/interface.md)).

---

## Rules

- Clear space on all four sides is the height of the yellow door — 3 units at the
  drawn scale. Nothing enters it.
- Never recolour the yellow. Never add a second accent.
- Never place `logo.svg` on a mid-tone background: it is a `currentColor` line
  drawing and needs a surface its ink contrasts with. Use `favicon.svg`, which
  brings its own tile.
- Never stretch, rotate, outline, or add an effect to it.
- Inline uses carry `aria-hidden="true"` and let the adjacent wordmark be the
  accessible name. A standalone use carries `role="img"` and a `<title>`.
