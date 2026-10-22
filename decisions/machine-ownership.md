# Machine ownership + the sharing allowlist

> Decided and built 2026-06-16. Replaced the `multi_tenant` boolean in
> [`blueprint/console/data-model.md`](../blueprint/console/data-model.md).

## The problem

`multi_tenant = true` meant any project could attach to a shared box, so client 3's box
could be picked up by client 4. There is one operator (clients are customers, not
logins), so the risk is a mis-click, not a breach — but the wrong client on the wrong
hardware mixes resources, billing and blast radius.

## The decision

A box has an **owner** (`Machine.owner` → Project) and an explicit **`sharing`**:
`dedicated` (owner only, default) · `everyone` · `list` (owner + the `MachineGrant`
allowlist). `Machine#permits?(project)` is the one guardrail behind the attach query and
the `ProjectMachine` join.

The registering project owns the box. Ownership can be transferred or released to no one.
Deleting an owner is blocked until its boxes move. Every change is a recorded act.

## Roads not taken

- **An Owner/Account layer above Project.** Project already is the client. Revisit if a
  client ever spans projects.
- **Blank allowlist = anyone.** A fresh box with no grants would read as wide open.
- **Silent nullify on owner delete.** Ownership never changes as a side effect.
- **Ownership on the app.** It is a property of the hardware, where the cost lives.

## Where it is enforced

`Machine#permits?`; `ProjectMachine`'s `machine_permits_project` validation;
`ProjectsController#destroy` owner guard; `MachinesController#sharing`/`#transfer` and
`MachineGrantsController`, each recording an `Event` before it acts. A transfer must name
its target, and release is asked for by name (`none`), never read from an empty pick. The
controls are on Machine Settings
([`machine-settings-is-a-page.md`](machine-settings-is-a-page.md)). Schema:
`machines.owner_id`, `machines.sharing`, `machine_grants`.
