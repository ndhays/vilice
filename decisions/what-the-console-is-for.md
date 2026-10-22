# What the console is for

> Decided 2026-09-29. Where acts sit on a page was later changed:
> [`acts-sit-with-what-they-act-on.md`](acts-sit-with-what-they-act-on.md).

## The question

The console wraps SSH commands. The CLI is good, and an AI agent can drive it as easily as
a person ([`orchestrators-are-clients.md`](orchestrators-are-clients.md)). What does a
Rails app add?

## The decision

The CLI is the product; the console is one client of it. **It is for three things an
agent at a shell does badly:**

1. **Watching** — showing what you did not think to ask about: memory, disk, drift,
   pending updates. An agent answers questions; a page shows the box at 91% disk you had
   forgotten.
2. **One shared record** — a durable, merged account a teammate, a client or an auditor
   can read without a shell. An agent session is gone when it ends.
3. **Bounded acts** — a button that can run `apply-updates` and nothing else is a real
   thing to hand a non-expert. An agent holding the same key is not bounded that way.

**Running commands is not on the list.** A write is a shortcut, and it never hides what
it does.

## Plain on the surface, exact underneath

The page interprets: a dot and "Online", "3 OS updates waiting". The exact form is one
step down:

- **The record is the technical view.** An entry carries the command that ran and its
  raw output. The preview before Confirm is the entry-to-be, so it shows the full command.
- **Every interpretation discloses its source** — a card opens to the command it was
  read from and the raw reply.

**The one bridge on the surface is the button.** Every act is a vilice command, so its
button carries the Vilice mark and the verb — `apply-updates`, mono, lowercase, filled —
with a plain sentence beside it. Someone who presses it a few times knows the command.

**What a command does on the box comes from the binary.** `vilice _commands` describes
every verb ([`help-is-the-documentation.md`](help-is-the-documentation.md)). Where it
lacks detail, it grows there, and that detail belongs in the record entry.

## How this sits with Shape B

[`ui-shape.md`](ui-shape.md) still holds: the record is the spine, and dangerous acts
want deliberate buttons rather than a text box. This changes what a button says.

## Roads not taken

- **Plain-word buttons** ("Apply now"). They hide the one word that would let you run it
  yourself, ask the operator to trust the wrapper, and teach nothing.
- **Commands on the surface.** Built briefly: each act listed its full `vilice …` line.
  The page read like a terminal and the GUI interpreted nothing. The command moved into
  the preview and the record.
- **Drop writes; make the console a cheat sheet.** Throws away bounded acts — the one
  write-side thing an agent cannot offer. Everyone who acts would need a shell key.
- **Host an agent in the console.** Competes where an agent at a shell is already
  better, and a free-text path to acts is what Shape B rejected. An agent gets its own
  scoped key ([`open/vilice-mcp.md`](open/vilice-mcp.md)).
- **A separate actions page.** You act on the thing you are looking at; a separate page
  loses the observed state that decided the act.
- **Two zones on every page — Observe beside Operate.** The first answer to where acts
  sit, built and then replaced: see
  [`acts-sit-with-what-they-act-on.md`](acts-sit-with-what-they-act-on.md).
