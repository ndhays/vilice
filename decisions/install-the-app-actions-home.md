# The App is the app-actions home

**Decided 2026-06-13.** Where app lifecycle acts live in the console. Refines
[open/ui-roadmap.md](open/ui-roadmap.md) §"a view shows what it's FOR".

## Decision

**Lifecycle acts on an app — roll back, start, stop, restart, remove a placement — live on
the App page**, in its project context. The App is the root domain object (it *is* the
deploy spec, `App#deploy_envelope`); an operator manages an *app* there: "redeploy my
app", "roll it back". For a single placement the box is implied; for replicas you act per
placement.

**The machine page acts on the box.** Machine-level acts (apply OS updates, send a
balancer its edge table), and the two app acts that need no project at all: **deploy** an
app to this box, and **remove** an app from it. Its app list links each app to its App
page, with the project it serves.

## Why

**Two mental models, one home each.** An operator who thinks in *app + hostname +
is-it-green* treats the machine as plumbing and should never have to find the box their
app runs on to manage it — so app lifecycle lives on the App. An operator looking at a box
thinks in *what runs here*, and the machine page is that view.

**They are two layers, not two doors to one act.** The machine page is the base layer:
it acts on a box with no Project and no stored plan, sending the spec and keeping nothing
— which the App cannot do. The App places one app across several boxes and keeps the plan
— which the machine page cannot do. Each has an act the other cannot express, so neither
is a duplicate of the other. What *would* be a duplicate is the same lifecycle verbs in
both places, and that is the thing kept out.

## Mechanism (no new ceremony)

The witnessed ceremony is one route, keyed to a machine (the SSH target); its `from`
param decides where it returns (`app` → the App page, otherwise the machine page). The
lifecycle verbs are the `apps/_acts` partial, rendered only on the App page. The allowlist
(`Mutation::ACTS`) and the record-before-act invariant hold wherever an act is triggered.

## Roads not taken

- **The same lifecycle verbs on the machine page too**, as a "sysadmin lens." Tried, and
  reversed: two places to do one act, against a model that wants one home per act.
- **A machine page with no app acts at all**, read-only for apps. Also tried, and
  reversed once the machine view became the base layer: it left no way to put an app on
  a box without first making a project and a stored plan.
- **A separate App-scoped ceremony route.** The act needs a machine regardless; the `from`
  hint is enough. One ceremony, parameterized by where it was launched.
