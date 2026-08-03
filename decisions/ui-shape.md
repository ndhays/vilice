# Steward Console UI — the record is the spine (Shape B)

The settled choice of what Steward Console's UI is *about*, and the two shapes rejected to get
there. The canonical description of the resulting interface is in
[`blueprint/console/interface.md`](../blueprint/console/interface.md); the build
roadmap and screens still ahead are in
[`decisions/open/ui-roadmap.md`](open/ui-roadmap.md).

## The question

Is the protagonist of the UI the **state** (what is true now) or the **record** (what
happened, who did it, what it touched)?

## The decision

The **record**, with current state as just *the head of the record*. The reason Steward Console
exists is the witnessed, append-only, hash-chained record and un-bypassability — so the UI
must make that the spine, not bury it under a state dashboard. This is the one thing no
competitor can copy, because they don't keep the chain.

Everything in the interface follows: the one-page pattern (chain as the page body, not a
footer), the mutate ceremony (the record-before-act invariant *is* the confirm dialog), and
"state is the head of the record."

## Roads not taken

- **Shape A — a refined admin panel** (inherit the old `switchyard-platform` structure:
  "here are my machines and apps; here are buttons"). Lowest risk, but it makes the new
  platform's whole reason for existing **invisible** — it ships Kamal-with-an-audit-log.
  Worth stealing polish from; wrong as the spine.
- **Shape C — a command surface** (keyboard-first console, state-as-query). Too clever for
  the mutate side — dangerous acts *want* deliberate buttons, not a text box. Its one good
  idea, a command palette, is folded into Shape B for **nav + observe only**, kept off the
  mutate path.

## A consequence worth recording: Dispatcher is dropped

"Operator vs Dispatcher" was a persona/mode split. The pivot dissolved it: one Rails app
reaches Steward over scoped SSH and runs anywhere, so the difference is only *how many
`Machine` rows you have* — the lens widens, same code, no mode. What was genuinely unique
to "Dispatcher" — remote reach and multi-operator delegation — survives as plain features,
not a second app. (If the name returns, it is the literal traffic-dispatching front box of
the load-balancer tier — a Caddy box Steward manages, not a new program. See
[`decisions/open/console-open-questions.md`](open/console-open-questions.md).)
