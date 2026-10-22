# The App is the app-actions home

> Decided 2026-06-13. **Partly superseded 2026-10-05:** every app on a box now has its
> own page there with its acts
> ([`acts-sit-with-what-they-act-on.md`](acts-sit-with-what-they-act-on.md)), so the
> machine side no longer holds only `deploy` and `remove`. The App-page half stands.

## The decision

**Lifecycle acts on an app — roll back, start, stop, restart, remove a placement — are
on the App page**, per placement. The App is the deploy spec (`App#deploy_envelope`), and
an operator who thinks in *app + hostname + is it green* should not have to find the box
to manage it.

**The machine page acts on the box:** apply OS updates, send a balancer its table, and
deploy an app with no project at all.

## Why two layers

The machine page is the base layer: it acts on a box with no Project and no stored plan,
sending the spec and keeping nothing. The App places one app across several boxes and
keeps the plan. Each has an act the other cannot express.

## Mechanism

The ceremony is one route, keyed to a machine (the SSH target). Its `from` param decides
where it returns. The allowlist (`Mutation::ACTS`) and record-before-act hold wherever
an act starts.

## Roads not taken

- **The same lifecycle verbs on the machine page too**, as a "sysadmin lens". Tried and
  reversed in June: two places for one act. **This is the road the 2026-10-05 decision
  took again**, on a page per app rather than on the machine page. The duplication is an
  open question in [`open/ui-roadmap.md`](open/ui-roadmap.md).
- **A machine page with no app acts at all.** Left no way to put an app on a box without
  first making a project and a stored plan.
- **A separate App-scoped ceremony route.** The act needs a machine regardless.
