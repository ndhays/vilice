# Acts sit with what they act on

> Decided 2026-10-05. Spec:
> [`blueprint/console/interface.md`](../blueprint/console/interface.md). Supersedes the
> two-zone layout in [`what-the-console-is-for.md`](what-the-console-is-for.md) and the
> machine-page half of [`install-the-app-actions-home.md`](install-the-app-actions-home.md).

## The decision

**Each act sits in the card it acts on, beside the reading that prompts it.**

- **A quick view, then one level down.** The machine page is for looking: the box's
  numbers, one line for each thing about it saying how it is, and one line per app.
  Each leads down — a status chip to the **Machine Status** page, an app line to
  that app's page — and the detail and the acts are there.
- **Machine Status holds the machine's acts**, each beside its reading: Maintenance has
  `apply-updates`, Record has the record's own `backup`. `deploy` stays with the apps
  list and `route` with the edge card, since neither acts on one thing with a page.
- **Registries is machine-level**, a part of Machine Status, with `registry-login` and
  `registry-logout`. A
  registry login is a box credential
  ([`registry-credentials.md`](registry-credentials.md)), so it is read and changed at
  machine level.
- **Every app on a box has its own page** (`/machines/:id/apps/:name`). The machine page
  shows one line per app with its state; the line leads to the page, which holds that
  app's acts: deploy, rollback, start, stop, restart, remove, backup, restore. The app is
  named by what the box calls it, so an app with no console `App` behind it has the page
  too. Before, it had only a row with `remove`.
- **Backups follow the app**, because `backup` is per app. The machine page keeps only
  the record's own snapshot.

## Machine level or app level

**A thing lives where you change it.** A registry login is changed on the box and shared
by apps: machine. A certificate is stored by Caddy for the box, but it exists because one
app's spec names a hostname, and you change it by changing the app: it is the app's, and
the machine page only rolls them up, each row naming its app. The record's backup,
updates, and who can reach the box are the machine's. An app's backup, logs and lifecycle
are the app's.

## What had to survive

The two zones existed so a reader never has to work out which kind of control they are
looking at. **The button carries that now.** A button that sends a vilice command has the
mark and the verb, filled: blue for a read, violet for an act, red for one that takes
something away. Nothing else looks like it. The preview opens in the card the button was
pressed in, and it is still the record-before-act step.

An observe key reads every card and is offered no act. An unreachable box shows one card
and no act.

## Where the mechanism is

- `Mutation::ACTS` is still the one allowlist. An app-scoped act binds to an `App` we
  hold, or to **the name the box reports** — checked against `App::NAME_FORMAT`, because
  it is written into a command. `deploy` needs an `App`: a name carries no spec.
- `registry-logout` takes a registry host, checked against `Mutation::REGISTRY_FORMAT`.
- The frame a preview opens in comes from the page, so it is checked against a fixed
  pattern (`MutationsController::FRAME_FORMAT`).

## Registry login passes a password through

`registry-login` is the one act here that carries a secret. The console sends it to the
box on stdin and keeps nothing: no column, no `Event` field, no log line. Afterwards the
box holds the credential and the console does not, which is the line
[`a-tag-is-not-a-release.md`](a-tag-is-not-a-release.md) draws — the console *storing* a
registry credential is still refused.

It is a form of its own, not a ceremony act. The ceremony's compose step submits by GET,
so a password in it would land in a URL.

## Roads not taken

- **Every card open on the machine page, in two columns, acts and all.** The first form.
  Everything was visible and nothing stood out: a healthy registry login took the same
  room as a failing backup, and the page was long before it reached the record.
- **Accordions.** Built next: each machine-level thing a collapsed section with a
  summary, opening itself when it had a problem. Dropped for the plainer pattern the
  apps already had — a line says how the thing is, and a click goes to its page. One
  pattern for both levels, a link you can send, and no state hidden in what is open.
- **Two zones, Observe beside Operate.** Built, and replaced. Where a control sat said
  what it was, but the reading that prompts an act and the act itself were on opposite
  sides of the page, and an app with no console `App` had nowhere for its acts at all.
- **A separate actions page.** Already rejected in
  [`what-the-console-is-for.md`](what-the-console-is-for.md): you act on the thing you
  are looking at.
- **Operate as approve/deny of an agent's proposal**, which would have made where a
  button sits matter less than where a proposal lands. Not built —
  [`no-console-gate.md`](no-console-gate.md).
- **Keep `remove` as a row button with a browser confirm.** It was the only act that
  skipped the preview. It goes through the ceremony like the rest.
- **A registry credential stored in the console**, so a login could be re-sent. A new
  class of secret in the control plane, for a convenience.
- **Backups as one machine card listing every app.** The reading was there and the act
  was not; `backup` and `restore` take an app.

## Still open

- **The App page still carries the lifecycle verbs per placement**, and each placement
  now also has a page on its box with the same verbs. That is two places for one act,
  which [`install-the-app-actions-home.md`](install-the-app-actions-home.md) set out to
  avoid. Tracked in [`open/ui-roadmap.md`](open/ui-roadmap.md).
- **Restart and the maintenance window** have no verb, so the Maintenance card has no
  button for them ([`open/vilice-open-questions.md`](open/vilice-open-questions.md)).
