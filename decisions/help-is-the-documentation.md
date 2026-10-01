# The help page is the documentation

**Settled 2026-08-09.**

Every page under `/commands/` on the documentation site opens with the literal
output of `vilice <name> --help` — the bytes the binary printed, captured at build
time by `vilice _commands`. The site does not describe the CLI. It prints it.

## The problem

The site carried two hand-written Markdown tables — "Root Commands" and "Vilice
Commands" — restating what `core.Commands` already knew: every verb, its scope, its
synopsis, and a sentence about it. Meanwhile `vilice deploy --help` printed four
lines: a summary, a synopsis, and a scope. No flag descriptions, no examples.

So the good description of the CLI was on a web page the operator was not looking
at, and the person at the terminal — the one actually about to change a machine —
got the thin one. And the two could drift, because nothing connected them.

The CLI already claimed "one source, three views": help, usage errors, and
`vilice(1)` all render from `core.Commands`. The claim was true and worth very
little, because the source was too thin for any of the three views to be good.

## What we chose

Make the source thick enough to publish, then publish it.

`core.Command` gained `Long` (a paragraph), `Examples`, and a `Flags` list that
carries a description per flag. `commandHelp` renders a full page from those.
`vilice _commands` emits the table as JSON with each command's rendered page
included, and the site's `help.js` reads it at build time.

There is exactly one renderer. A published page and a terminal cannot disagree,
because the published page *is* the terminal's output — a test asserts they are
byte-identical.

Three properties fall out of this that we would otherwise have had to maintain by
hand:

- **A flag cannot exist undocumented.** The `Flags` list is what the gate checks an
  invocation against (`unknownFlag`) *and* what help prints. Adding a flag without a
  description fails `core.CheckDocs`, which the Go test suite runs against the
  assembled binary.
- **The docs cannot outgrow the terminal.** Help output is capped at 78 columns and
  checked. That is not house style: the site renders the text in a fixed-width block,
  so an overrun is a horizontal scrollbar for every visitor.
- **The site's taxonomy is the binary's.** The sidebar and the index group commands
  by `core.Groups`, the same list `vilice help` uses. The site cannot invent a
  structure the CLI does not have.

## The road not taken

**Hand-written reference pages, richer than `--help`.** This is what most projects
do, and it buys real things: prose, cross-links, screenshots, a page that can be
better than a terminal allows.

Rejected, because the CLI is the interface people actually use. A second description
of it is a second thing to be wrong, and the second one is the one that gets updated
— the web page is where a writer's attention goes, and the terminal quietly rots.
That is precisely backwards for a tool whose entire argument is that you can check it
by eye, on the box, with no other artifact in hand. `vilice help deploy` on a machine
with no browser has to be the good version.

The cost is real and accepted: a command page is as good as its help text and no
better. When a page reads thin, the fix is in `dispatch.go` or `verbs.go`, and it
improves the terminal at the same time. That is the incentive we wanted.

`content/commands/<name>.md` exists for the residue — a caveat, a pointer at a
decision record — and is empty for most commands on purpose. A command that needs a
lot of site-only prose is a help page that needs improving.

## Consequences

- The site build depends on the binary: `npm run serve` and `npm run build` both run
  `make -C ../vilice build` first, and `help.js` fails loudly if it is missing.
  The docs are downstream of the code, which is the direction we want.
- `vilice(1)` renders `Long`, flags, and examples too. Three views, one source, all
  three now the same depth.
- The command tables are gone from `site/content/index.md`, which is roughly 100
  lines shorter for it.

See `blueprint/design/patterns.md` for the page's shape, and `site/README.md` for
the build wiring.
