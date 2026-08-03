# site

The Steward documentation site, built with [Web Origami](https://weborigami.org).

```bash
npm install
npm run serve     # local preview
npm run build     # → dist/  (drag-and-drop deploy)
```

## How it's wired

- `content/*.md` — the pages (Markdown + front-matter `title`). One file per page.
- `page.ori` — the shared HTML layout (header, nav, footer).
- `site.ori` — the build tree: which content files become which pages, plus assets.
- `assets/` — `styles.css` and `favicon.svg`.
- `versions.js` — reads component versions at build time (currently `steward/version.go`).

## Conventions (the "preferences")

There is no separate settings file — conventions live here; presentation lives in
`assets/styles.css` and `page.ori`.

- **Headings use Title Case** (Headline Style): *The Legible Ceiling*, *Deploy &
  Lifecycle*. Body text is sentence case.
- **Heading anchors are automatic.** Origami slugifies heading text into an `id`
  (e.g. `## The Legible Ceiling` → `id="the-legible-ceiling"`; `&` and `—` are
  dropped, leaving the surrounding hyphens). Link to those slugs directly.
- **Long pages open with a Contents line** of `·`-separated anchor links for fast
  jumping (see `steward.md`).
- **Copy is true or absent.** Document only what's settled; leave gaps for the
  blueprints to fill rather than describe what's still up in the air.
- **Bias to subtraction.** A page, section, or line earns its place or it goes.
  Prefer merging over adding, and cutting over hedging — for a technical app or
  docs site, less surface is the feature. When in doubt, leave it out.
