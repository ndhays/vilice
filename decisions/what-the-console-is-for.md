# What the console is for

> Decided 2026-09-29, after a human pass over the console. The CLI is the product; the
> console is one client of it. It earns its place by **watching**, by keeping **one shared
> record**, and by **bounded acts** — and every act shows the command it runs.

## The question

The console wraps SSH commands. Vilice's CLI is good, and an AI agent can drive it as
easily as a person can — [`orchestrators-are-clients.md`](orchestrators-are-clients.md)
names the agent as a client alongside the console. So what does a Rails app add that a
shell, or an LLM at a shell, does not?

Testing *Apply now* against a live box made the gap concrete: the button worked, and the
way to check it had worked was a list of commands (`apt list --upgradable`,
`/var/log/apt/history.log`, `vilice record`) the page never mentioned.

## The decision

**The console is for three things an LLM at a shell does badly:**

1. **Watching** — showing what you did not think to ask about. Memory, disk, drift,
   pending updates, what needs attention across the fleet. An agent answers questions;
   a page shows you the box at 91% disk you had forgotten.
2. **One shared record** — a durable, merged account of acts that a teammate, a client or
   an auditor can read without a shell. An agent session is gone when it ends.
3. **Bounded acts** — a button that can run `apply-updates` and nothing else is a real
   thing to hand a non-expert. An agent holding the same key is not bounded the same way.

**Running commands is not on the list.** An agent will always be more flexible at that,
and the console should not compete. So a write is a *shortcut* — and it never hides what
it does, but it does not make you read it either.

**Plain on the surface, exact underneath.** The page interprets: a dot and "Online", "3
OS updates waiting", memory as a card. It is a GUI and uses being one; an operator who
knows the CLI still wants the easy read. The exact form — the command, and what it
returned — is always one step down, never on the surface:

- **The record is the technical view.** An entry carries the command that ran and, where
  there is one, its raw output. The preview before Confirm is the entry-to-be, so it shows
  the full command too.
- **Every interpretation discloses its source.** A card read from the box can open to the
  command it came from and the raw reply (*Raw status output*: `vilice status --json`,
  then the JSON).

**The one bridge on the surface is the button.** Every act is a vilice command, so its
button carries the Vilice mark and the verb — `apply-updates`, mono, lowercase, filled —
and a plain sentence beside it says why you would press it. The mark says *this calls
into Vilice* before you read the word; the word is the one you would type. Nothing that
does not call Vilice looks like that. (Road not taken: plain-word buttons — "Apply now" —
which hid the one word that would let you run it yourself.) Someone who presses the
button a few times knows the command and can run it, or ask an agent to.

**What a command does on the box comes from the binary, not the console.** `vilice
_commands` already describes every verb
([`help-is-the-documentation.md`](help-is-the-documentation.md)). A hand-written copy of
"what apply-updates does" in the console would be a second description of the CLI, free to
drift. Where `_commands` lacks the detail, it grows there — and it belongs in the record
entry, not on the page.

## Where acts sit

Every entity page splits into two zones, side by side: **Observe** holds what the box
reports and no act at all; **Operate** holds every act, and the ceremony opens there.
Which kind of control you are looking at is answered by where it sits, not by reading it.
The header is the name and one live signal — a dot and plain words — and what a thing
*is* reads as a short labelled list in a fixed order.

## How this sits with Shape B

[`ui-shape.md`](ui-shape.md) still holds: the record is the spine, and dangerous acts want
deliberate buttons rather than a text box (Shape C's objection). This decision does not
bring the text box back. It changes what a button *says*, not whether there is one.

## Roads not taken

- **Commands on the surface.** Briefly built: each act listed its full `vilice …` line
  on the page. Honest, but it made the page read like a terminal and left the GUI doing
  none of the interpreting it is for. The command moved down, into the preview and the
  record; the button kept the verb.
- **Keep hiding the command** (the console as first built). A button that says "Apply now" and
  nothing more asks the operator to trust the wrapper. It also leaves them with no path to
  verify, and teaches nothing — every press keeps them dependent on the page.
- **Drop writes; make the console a cheat sheet.** Show the commands to copy and let the
  operator run them. Honest, but it throws away bounded acts — the one write-side thing an
  agent cannot offer. Everyone who acts would need a shell key of their own.
- **Host an agent in the console.** A chat box that runs Vilice verbs. It would compete
  on the ground where an agent at a shell is already better, and a free-text path to acts
  is exactly what Shape B rejected. If an agent needs Vilice, it gets its own scoped key
  ([`open/vilice-mcp.md`](open/vilice-mcp.md)).
- **A separate actions page.** Every act in one place, apart from what it acts on. Clean
  to draw, but you act on the thing you are looking at: a separate page makes you carry
  the box and the app across in your head, and loses the observed state that decided the
  act. A zone on the same page keeps both.
