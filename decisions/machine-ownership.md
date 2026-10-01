# Machine ownership + the sharing allowlist

**Status:** settled + built (2026-06-16). Replaced **Decision 1**'s `multi_tenant`
boolean in [`blueprint/console/data-model.md`](../blueprint/console/data-model.md);
graduated from `decisions/open/`.

## The problem

`multi_tenant = true` meant "any project may attach," unbounded: the attach dropdown
surfaced every shared box to every project, so client 3's box could be picked up by
client 4. "Shared" meant *shared with the whole fleet*, with no notion of **whose** box
it is. Single-operator system (clients are customers, not logins), so the risk is an
operator fat-fingering a cross-client placement, not a breach — but wrong client on
wrong hardware mixes resources, billing, and blast radius, so it earns a guardrail.

## The decision

A box has an **owner** (`Machine.owner` → Project) and an explicit tri-state
**`sharing`**: `dedicated` (owner only, default) · `everyone` (open) · `list` (owner +
the `MachineGrant` allowlist). `Machine#permits?(project)` is the single guardrail
behind both the attach query and the `ProjectMachine` join. The registering project
owns the box; ownership can be **transferred** to another project or **released** to no
one. Deleting an owner is **blocked** until its boxes move. Unowned boxes are surfaced
on the fleet page (inert until re-owned or shared). Every change is a recorded act.

## Roads not taken

- **An Owner/Account layer above Project.** Project already *is* the client (1:1,
  `identifies :entity`), so a per-box owner + allowlist is enough — a new tenancy entity
  would be weight we don't need before beta. (Revisit if a client ever spans projects.)
- **Implicit "blank allowlist = anyone."** Rejected as a footgun: a fresh box with no
  grants would read as wide-open. Sharing is an **explicit** tri-state instead — a box
  is `dedicated` until someone chooses otherwise.
- **Silent nullify on owner delete.** Rejected: ownership never changes as a side
  effect. Deleting an owning project is blocked; the operator transfers or releases
  first (release-to-unowned is the deliberate, recorded "remove ownership" act).
- **App-field registry/per-install ownership.** Ownership is a property of the *box*
  (hardware), not the app — keeps the boundary where the cost actually lives.

## Mechanism (where it's enforced)

`Machine#permits?` (owner / `everyone` / `list`+grant); `ProjectMachine`
`machine_permits_project` validation; `ProjectsController#destroy` owner guard;
`MachinesController#sharing`/`#transfer` + `MachineGrantsController` (each records an
Event before it acts). The controls live on Machine Settings
([`machine-settings-is-a-page.md`](machine-settings-is-a-page.md)); a transfer must name
its target, and releasing is asked for by name (`none`), never read from an empty pick. Schema: `machines.owner_id`, `machines.sharing`, `machine_grants`.
