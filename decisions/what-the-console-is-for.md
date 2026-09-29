# What the console is for

> Decided 2026-09-29, after a human pass over the console. The CLI is the product; the
> console is one client of it. It earns its place by **watching**, by keeping **one shared
> record**, and by **bounded acts** — and every act shows the command it runs.

## The question

The console wraps SSH commands. Steward's CLI is good, and an AI agent can drive it as
easily as a person can — [`orchestrators-are-clients.md`](orchestrators-are-clients.md)
names the agent as a client alongside the console. So what does a Rails app add that a
shell, or an LLM at a shell, does not?

Testing *Apply now* against a live box made the gap concrete: the button worked, and the
way to check it had worked was a list of commands (`apt list --upgradable`,
`/var/log/apt/history.log`, `steward record`) the page never mentioned.

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
and the console should not compete. So a write is a *shortcut*, and it never hides what
it does. Every act shows three layers, in the preview and again on the record entry:

```
Apply updates                                    ← plain words
steward apply-updates                            ← what the console sends
  → apt-get update -y; apt-get upgrade -y        ← what that does on the box
Check it:  apt list --upgradable · tail /var/log/apt/history.log
```

The plain line serves the non-expert, the command lines serve the expert, and both read
the same entry. That is the bridge: one funnel, two readers. Someone who presses the
button a few times has seen the commands and can run them — or ask an agent to.

**The third layer comes from the binary, not the console.** `steward _commands` already
describes every verb ([`help-is-the-documentation.md`](help-is-the-documentation.md)). A
hand-written copy of "what apply-updates does" in the console would be a second
description of the CLI, free to drift. Where `_commands` lacks the detail, it grows there.

## How this sits with Shape B

[`ui-shape.md`](ui-shape.md) still holds: the record is the spine, and dangerous acts want
deliberate buttons rather than a text box (Shape C's objection). This decision does not
bring the text box back. It changes what a button *says*, not whether there is one.

## Roads not taken

- **Keep hiding the command** (the console as built). A button that says "Apply now" and
  nothing more asks the operator to trust the wrapper. It also leaves them with no path to
  verify, and teaches nothing — every press keeps them dependent on the page.
- **Drop writes; make the console a cheat sheet.** Show the commands to copy and let the
  operator run them. Honest, but it throws away bounded acts — the one write-side thing an
  agent cannot offer. Everyone who acts would need a shell key of their own.
- **Host an agent in the console.** A chat box that runs Steward verbs. It would compete
  on the ground where an agent at a shell is already better, and a free-text path to acts
  is exactly what Shape B rejected. If an agent needs Steward, it gets its own scoped key
  ([`open/steward-mcp.md`](open/steward-mcp.md)).
