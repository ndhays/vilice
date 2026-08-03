# Drift is surfaced, never closed

> Decided 2026-08-03, while working out what the intention layer is for. Promoted out
> of [`one-primitive-composed.md`](one-primitive-composed.md), which had the rule buried
> in a doc about something else and had argued both sides of it. Follows from
> [`orchestrators-are-clients.md`](orchestrators-are-clients.md).

## The question

Once something states *this app should run on boxes A, B and C*, reality can disagree
with it. Someone opens box A and removes the app. Now the stated intention and the
machine differ.

Every other tool in this category closes that gap automatically. Kubernetes reconciles
continuously; Chef and Puppet converge on a schedule; that is the entire promise of
declarative infrastructure. The obvious thing to build is a reconciler.

## The decision

**Nothing auto-converges. The gap is made visible; closing it is an act.**

If the control plane silently redeployed the app onto box A, a deliberate, recorded
human decision — `remove`, with a named actor and a chain entry — would be undone by a
machine acting with no actor and no entry of its own. That is precisely the shape
[`orchestrators-are-clients.md`](orchestrators-are-clients.md) refuses: something with
power over the box that does not come through the door.

An auto-reconciler is a daemon by another name. It does not matter that it drives
Steward rather than Podman; what matters is that it decides, and nothing named decided.

So: the console shows *intention: 3 boxes · reality: 2*, and offers a button. A person
presses it, the call goes through the same scoped door as everything else, and **that**
is recorded — with who pressed it. Reconciling is not a background process; it is a
witnessed act like any other.

## Why this is the good property, not the compromise

Both halves of a disagreement are already accountable here. The box's chain says who
removed the app and when. The intention says who asked for three and when. **The gap
between them is fully attributable** — which is unusual, and only possible because
neither side is allowed to silently rewrite the other.

Auto-convergence destroys exactly that. When the system closes the gap on its own, the
human decision that opened it is erased: the end state looks as though nobody ever
removed anything. A record that can be quietly overwritten by a reconciler is not much
of a record.

This is the sharpest illustration of what the whole design is for. Everyone else's
system answers "what is running?" Ours also answers "who decided that, and did anyone
disagree?"

## What it costs

Real work does not converge on its own. A fleet operation is **N recorded acts, not one
atomic act**: a sequence that fails halfway leaves the fleet halfway, and recovery is
another sequence of named calls. There is no cross-box transaction and there will not
be one. Nobody gets woken at 3am by a self-healing system, because there isn't one —
they get woken by a page that says three boxes were asked for and two are serving.

We take that trade deliberately. It is the same trade as no-shell and
record-before-act: convenience given up for the ability to say, afterwards, exactly what
happened and who is answerable for it.

## Two corollaries

**Deleting an intention must not touch a box.** Deleting a statement of desire is not an
act on a machine. A cascade that fires N destructive calls whose only trace is a
vanished row is the same failure in a different costume. Removing the apps is a separate,
explicit choice that *composes* N recorded removals — which is precisely the ceremony
`steward uninstall` already performs on the box, where `--remove-apps` is opt-in and the
plan is printed first ([`uninstall-removes-the-gate.md`](uninstall-removes-the-gate.md)).

**An intention never renders as state.** It is a claim about what was asked for; reality
comes from the box. The UI must show them as two visibly different things, or the
distinction that makes drift meaningful disappears the moment someone reads the screen.
This is [`ui-shape.md`](ui-shape.md)'s "state is the head of the record", one layer up.

## Roads not taken

- **Continuous reconciliation** (the Kubernetes model). Rejected above: it erases the
  human decision that created the drift.
- **Reconcile on a schedule, with an audit entry.** Better, and still wrong — the entry
  would name the console as actor for a decision no person made. An actor that is always
  the same program is not accountability, it is a rubber stamp.
- **Auto-converge, but only "safe" directions** (add a missing replica, never remove).
  Tempting, and it fails on the case that matters: a human removed that app *on purpose*,
  and re-adding it is exactly the silent override. "Safe" is doing a lot of work in that
  sentence.
- **No intention layer at all** — only the machine view, and let operators track
  placement themselves. Coherent, and what the system does today. Rejected because
  "should this be running here?" is a real question and answering it in a spreadsheet is
  worse than answering it in the tool. The layer earns itself by making the gap visible,
  not by closing it.
