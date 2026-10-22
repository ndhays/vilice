# Vilice Console UI — the record is the spine (Shape B)

> Spec: [`blueprint/console/interface.md`](../blueprint/console/interface.md). What is
> still ahead: [`open/ui-roadmap.md`](open/ui-roadmap.md).

## The decision

The protagonist of the UI is the **record** — what happened, who did it, what it touched
— with current state as the head of the record. The witnessed, hash-chained record is the
reason the console exists, so the UI makes it the spine.

What follows: the chain is the page body, not a footer; the confirm dialog is the
record-before-act step; state is the head of the record.

## Roads not taken

- **Shape A — a refined admin panel** ("here are my machines and apps; here are
  buttons"). Lowest risk, and it makes the reason for the platform invisible: Kamal with
  an audit log. Worth stealing polish from.
- **Shape C — a command surface** (keyboard-first, state as query). Dangerous acts want
  deliberate buttons, not a text box. Its command palette is kept for nav and observe
  only.

## Dispatcher is dropped

"Operator vs Dispatcher" was a mode split. One Rails app reaches Vilice over scoped SSH
and runs anywhere, so the difference is only how many `Machine` rows there are. Remote
reach and multi-operator delegation survive as features, not a second app.
