# site

The Steward documentation site, built with [Web Origami](https://weborigami.org).

```bash
npm install
npm run serve     # local preview
npm run build     # → dist/  (drag-and-drop deploy)
```

Both scripts build the CLI first (`make -C ../steward build`), because the command
pages are generated from it. `build` additionally checks that the signed release for
the current `VERSION` is published — run `make -C ../steward release` first.

## How it's wired

- `content/*.md` — the hand-written pages (Markdown + front-matter `title`, `nav`).
- `content/commands/*.md` — optional prose appended to a command's page. Usually absent.
- `help.js` — **runs `steward _commands` at build time** and returns the command table:
  name, scope, group, summary, and the verbatim `--help` page for each.
- `command.ori` / `commandIndex.ori` / `sidebar.ori` / `sitemap.ori` — the generated parts.
- `page.ori` — the shared HTML layout (banner, header, sidebar, footer).
- `site.ori` — the build tree: which pages exist, plus assets, fonts, and releases.
- `assets/` — `tokens.css`, `styles.css`, `copy.js`, the mark.
- `versions.js` — reads the platform version from `VERSION` at build time.

Presentation is specified in `blueprint/design/` — tokens, the mark, and the shared
patterns. `assets/tokens.css` is a projection of `blueprint/design/tokens.md`; change
the document in the same commit.

## The command pages are generated

Every page under `/commands/` opens with the literal output of
`steward <name> --help`, captured from the binary at build time. **Do not describe a
command here.** If a page is missing something, the fix is in the CLI's command table
(`steward/internal/core/dispatch.go`, `steward/internal/app/verbs.go`) — that is
the one source, and `core.CheckDocs` fails the Go build if a verb ships without a
paragraph, a flag without a description, or a line too wide for the block it lands in.
See `decisions/help-is-the-documentation.md`.

`content/commands/<name>.md` is for what the help page genuinely cannot hold: a
caveat, a pointer at a decision record, a link to a related page. Most commands need
none — that is the point.

## Conventions (the "preferences")

There is no separate settings file — conventions live here; presentation lives in
`assets/` and `page.ori`.

- **Headings use Title Case** (Headline Style): *The Legible Ceiling*, *Build From
  Source*. Body text is sentence case.
- **Heading anchors are automatic.** Origami slugifies heading text into an `id`
  (e.g. `## The Ceiling` → `id="the-ceiling"`; `&` and `—` are dropped, leaving the
  surrounding hyphens). Link to those slugs directly.
- **Long pages open with a Contents line** of `·`-separated anchor links.
- **Copy is true or absent.** Document only what's settled; leave gaps for the
  blueprints to fill rather than describe what's still up in the air.
- **Bias to subtraction.** A page, section, or line earns its place or it goes.
  Prefer merging over adding, and cutting over hedging — for a technical app or
  docs site, less surface is the feature. When in doubt, leave it out.

## Origami notes, learned the hard way

- **Object literals need commas** between entries when they span lines. A missing
  comma parses without error and then recurses until Node runs out of heap.
- **A key shadows a module of the same name.** The generated folder is `commands`,
  so the module that feeds it had to be `help.js` — as `commands.js` it resolved as
  "traverse into `commands`, get `js`", which is a loop.
- **`page.ori` uses a plain template literal, not `Tree.indent`.** Indent would
  re-indent the multi-line body and corrupt whitespace inside `<pre>` — fatal here,
  where a `<pre>` holds verbatim terminal output.
