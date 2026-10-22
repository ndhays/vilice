# Drift is surfaced, never closed

> Decided 2026-08-03. Follows from
> [`orchestrators-are-clients.md`](orchestrators-are-clients.md). Schema:
> [`../blueprint/console/data-model.md`](../blueprint/console/data-model.md); rendering:
> [`../blueprint/console/interface.md`](../blueprint/console/interface.md).

## The decision

**Nothing auto-converges. The gap is made visible; closing it is an act.**

Something states *this app should run on boxes A, B and C*. Someone removes it from A.
If the control plane silently redeployed it, a recorded human decision — `remove`, with a
named actor — would be undone by a machine acting with no actor and no entry. An
auto-reconciler is a daemon by another name: it decides, and nothing named decided.

So the console shows *intention: 3 boxes · reality: 2* and offers a button. A person
presses it, the call goes through the scoped door, and that is recorded with who pressed
it.

## Why

Both halves of a disagreement are accountable here: the box's chain says who removed the
app, the intention says who asked for three. The gap is attributable only because neither
side may silently rewrite the other. Auto-convergence erases the decision that opened the
gap — the end state looks as though nobody removed anything.

## What it costs

A fleet operation is **N recorded acts, not one atomic act.** A sequence that fails
halfway leaves the fleet halfway, and recovery is another sequence of named calls. There
is no cross-box transaction and no self-healing.

## Where the mechanism is

- **The two halves never merge.** `App#count` is the claim; `App#serving_count` counts
  only placements the box reports running on a reachable machine. The gap is
  `placement_gap`, kept out of `App#state` so an intention is never drawn with the status
  glyph.
- **Placing is not closing.** `POST /apps/:id/placements` creates a `pending` placement
  and records a `placed` act. The gap narrows only when observe sees the placement
  `running`. The console cannot close its own gap by asserting anything.
- **There is no converger.** No job, callback or schedule writes a placement or issues a
  deploy. `FleetObserveJob` reads reality and never acts on the intention. The button
  appears only when the gap is negative; the over-served case gets no one-click trim,
  because silently removing a running app is the failure this refuses.

## Two corollaries

- **Deleting an intention must not touch a box.** `apps#update` restates
  `count`/`exposure` and reaches nothing else. Removing an app is still `remove`, an
  explicit choice that composes N recorded removals — as `vilice uninstall --remove-apps`
  does on the box ([`uninstall-removes-the-gate.md`](uninstall-removes-the-gate.md)).
- **An intention never renders as state.** It is a claim about what was asked for;
  reality comes from the box.

## Roads not taken

- **Continuous reconciliation** (the Kubernetes model). Erases the human decision.
- **Reconcile on a schedule, with an audit entry.** The entry would name the console as
  actor for a decision no person made — a rubber stamp.
- **Auto-converge only in "safe" directions** (add, never remove). Fails on the case that
  matters: a person removed that app on purpose, and re-adding it is the silent override.
- **No intention layer at all.** Coherent. Rejected because "should this be running
  here?" is a real question, and a spreadsheet answers it worse than the tool.
