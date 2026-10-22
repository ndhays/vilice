# The help page is the documentation

> Decided 2026-08-09. Page shape: `blueprint/design/patterns.md`; build wiring:
> `site/README.md`.

## The decision

Every page under `/commands/` on the site opens with the literal output of
`vilice <name> --help`, captured at build time by `vilice _commands`. The site does not
describe the CLI. It prints it.

`core.Command` carries `Long` (a paragraph), `Examples`, and `Flags` with a description
each. `commandHelp` is the one renderer, and a test asserts the published page and the
terminal output are byte-identical.

- **A flag cannot exist undocumented.** The `Flags` list is what the gate checks an
  invocation against (`unknownFlag`) and what help prints. A flag with no description
  fails `core.CheckDocs`.
- **The docs cannot outgrow the terminal.** Help is capped at 78 columns and checked,
  because the site renders it in a fixed-width block.
- **The site's grouping is the binary's** — `core.Groups`, the list `vilice help` uses.

## Road not taken: hand-written reference pages

Richer than `--help`, and what most projects do. Rejected because a second description is
a second thing to be wrong, and the web page is the one that gets the attention while the
terminal rots. For a tool you are meant to check by eye on the box, `vilice help deploy`
with no browser has to be the good version.

The cost: a command page is as good as its help text. When one reads thin, the fix is in
`commands.go` or `verbs.go`. `content/commands/<name>.md` holds only what help cannot — a
caveat, a link — and is absent for most commands.

## Consequences

- The site build depends on the binary; `help.js` fails loudly without it.
- `vilice(1)` renders the same fields.
