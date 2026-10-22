# No console gate for agents

> Decided 2026-10-05. Answers the one question
> [`open/agents-and-the-console.md`](open/agents-and-the-console.md) left for the console:
> whether to build the gate there first. The box-side gate stays open in that doc.

## The decision

**The console's operate does not become approve/deny of an agent's proposal.** The
console keeps its buttons, and each sits with what it acts on
([`acts-sit-with-what-they-act-on.md`](acts-sit-with-what-they-act-on.md)).

## What was declined

An agent holds an observe key and files a proposal — an exact command and spec — into
the Status inbox. A person previews it and presses Approve or Deny. On approve, the
console sends the command with its own operate key.

## Why not

The costs are the ones the open doc already listed for this form:

- **The gate would be the console's code.** The console still holds every operate key.
- **The box's record would say only `console`.** Who proposed and who approved would be
  in the console's record, which is not hash-chained
  ([`two-records.md`](two-records.md)).
- **It buys none of the gain** of the console holding no operate key.
- **It is a lot to build for an interim form:** a proposals model, an inbox entry, a way
  for an agent to file, and passkeys on Approve.

## What stands

- **The gate on the box** — the agent files on the box with its observe key, and the
  console's key can only approve what was proposed — is still where this should end up,
  and still open.
- **What a person can do today, with no code:** give the agent an observe key, and keep
  the operate key on a hardware key that needs a touch per use. One touch is one act.
