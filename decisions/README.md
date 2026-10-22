# Decisions

The settled *why*, one line per document. What the system *is* lives in
[`../blueprint/`](../blueprint/); what is still being decided lives in [`open/`](open/).

## The gate and the box

- [no-key-gets-a-shell](no-key-gets-a-shell.md) — every key resolves to a named command; the top scope grants and revokes, nothing else.
- [ceiling-is-the-machine](ceiling-is-the-machine.md) — only `prepare` and `harden` need root; granting runs as `_vilice`.
- [one-vilice-per-box](one-vilice-per-box.md) — one account, one record; the binary refuses to act as anyone else.
- [orchestrators-are-clients](orchestrators-are-clients.md) — anything that sequences work holds a scoped key and comes through the same door.
- [rendered-config-is-a-boundary](rendered-config-is-a-boundary.md) — every value is checked against an allow-list before it is written into a config file.
- [roles-not-packs](roles-not-packs.md) — no plugin layer; a box is prepared as a `host` or a `balancer`.
- [the-role-belongs-to-the-box](the-role-belongs-to-the-box.md) — the console reports a box's role and cannot set it.
- [machine-onboarding](machine-onboarding.md) — the root bootstrap is local; the console never holds root.
- [uninstall-removes-the-gate](uninstall-removes-the-gate.md) — uninstall takes Vilice off and leaves the apps and the record.
- [upgrading-is-install-then-prepare](upgrading-is-install-then-prepare.md) — no `upgrade` command; the gate cannot replace itself.
- [caddy-admin-socket](caddy-admin-socket.md) — Caddy's admin API is a Unix socket, opened by file ownership.
- [connection-limits-in-nftables](connection-limits-in-nftables.md) — a flood is limited per address in the kernel, not by a Caddy module. Not built.
- [what-a-container-can-reach](what-a-container-can-reach.md) — measured: not another app's port; yes the cloud metadata service.
- [the-vpn-is-not-a-control-path](the-vpn-is-not-a-control-path.md) — a private network may carry app traffic, never the operator. Not built.
- [borrowed-substrate](borrowed-substrate.md) — OpenSSH, Caddy, Podman, systemd and restic do the deep work.
- [security-audit](security-audit.md) — how the code, the box and the gate are each measured, and what runs when.

## The record

- [record-format](record-format.md) — a JSONL file with a sha256 chain; the schema only grows.
- [two-records](two-records.md) — the box's record and the console's; only the box's is hash-chained.
- [record-outcome-on-the-entry](record-outcome-on-the-entry.md) — an act's result settles once, on its own entry.
- [a-sample-is-not-an-act](a-sample-is-not-an-act.md) — status samples stay out of the chain.
- [observe-reconciliation](observe-reconciliation.md) — a read updates the console's mirror of the box, with no event.

## Deploying apps

- [declarative-deploy](declarative-deploy.md) — deploy sends the whole spec; secrets ride stdin, never the command line.
- [quadlet-deploy](quadlet-deploy.md) — apps are rootless Quadlet units, deployed blue/green, drained by the app.
- [stop-first](stop-first.md) — an app that locks its data declares `stop_first`: the old copy stops before the new one starts.
- [app-config-is-the-artifact](app-config-is-the-artifact.md) — a spec is addressed by its digest; a change mints a new one.
- [accessories-belong-to-one-app](accessories-belong-to-one-app.md) — a database beside an app, on a network only that app joins.
- [registry-credentials](registry-credentials.md) — a registry login belongs to the box, not to an app.
- [a-tag-is-not-a-release](a-tag-is-not-a-release.md) — the console looks a digest up once and never follows a tag.
- [backup](backup.md) — restic, over an app's declared volumes; no database drivers.
- [one-primitive-composed](one-primitive-composed.md) — App is intent; exposure and count replace "fleet"; the balancer is a role.
- [drift-is-surfaced-never-closed](drift-is-surfaced-never-closed.md) — nothing converges on its own; closing a gap is a recorded act.
- [provider-boundary](provider-boundary.md) — the cloud provider is a lifecycle adapter; bare SSH is the floor.

## The console

- [what-the-console-is-for](what-the-console-is-for.md) — watching, one shared record, bounded acts; every button names its command.
- [ui-shape](ui-shape.md) — the record is the spine of the UI.
- [console-layers](console-layers.md) — three rings: machine view, placement, tenancy; each optional above the last.
- [acts-sit-with-what-they-act-on](acts-sit-with-what-they-act-on.md) — each act is in the card it acts on; every app on a box has a page.
- [install-the-app-actions-home](install-the-app-actions-home.md) — the App page holds lifecycle verbs per placement. Partly superseded.
- [no-console-gate](no-console-gate.md) — the console does not become approve/deny for an agent's proposals.
- [status-is-an-inbox](status-is-an-inbox.md) — the home page shows what needs you, or nothing.
- [the-record-is-a-list-not-a-chain-drawing](the-record-is-a-list-not-a-chain-drawing.md) — no rail between entries; a row states facts about itself.
- [the-rail-shows-the-layering](the-rail-shows-the-layering.md) — the nav is three bands, floor first.
- [group-the-fleet-dont-filter-it](group-the-fleet-dont-filter-it.md) — the Machines list groups; ownership is one grouping among others.
- [machine-settings-is-a-page](machine-settings-is-a-page.md) — ownership, sharing, the key and removal have their own page.
- [machine-ownership](machine-ownership.md) — a box has an owner and an explicit sharing mode.
- [machine-name-mirrors-the-box](machine-name-mirrors-the-box.md) — a machine's name is the box's hostname, not typed.
- [apps-and-placements](apps-and-placements.md) — the model names: AppTemplate, App, Placement.
- [app-library-manifest](app-library-manifest.md) — the App Library imports and exports as a YAML manifest.
- [appearance-belongs-to-the-operator](appearance-belongs-to-the-operator.md) — theme and mode are stored on the user.
- [console-build-choices](console-build-choices.md) — Rails 8 auth, Boxcar used sparingly, the cache store.
- [secrets-come-from-the-deployment](secrets-come-from-the-deployment.md) — the repo ships no credentials; production reads its keys from the environment.
- [the-console-image-is-built-from-a-commit](the-console-image-is-built-from-a-commit.md) — `make image`: Boxcar and VERSION as build contexts, tagged by commit, deployed by digest.
- [scenario-seeds](scenario-seeds.md) — named dev scenarios, and a dev-only fake for machine health.

## The project

- [the-name-is-vilice](the-name-is-vilice.md) — the name, the domains, the publish gate, and what is still to do.
- [the-core-is-handwritten](the-core-is-handwritten.md) — the core will be rewritten by hand and hosted on Codeberg; the release key rule.
- [licensing](licensing.md) — MIT for the CLI, AGPL for the console, no CLA.
- [versioning](versioning.md) — a version is one set of bytes forever; fix forward.
- [help-is-the-documentation](help-is-the-documentation.md) — the docs site prints `--help` verbatim.
