# The console is layered too — three rings, one app

> Decided 2026-08-03. Written when Vilice had a plugin ("pack") layer; that is gone
> ([`roles-not-packs.md`](roles-not-packs.md)). The argument stands.

## The problem

The console was three things under one name: you could not deploy an app without first
inventing a client, because `App belongs_to :project` was required.

## The decision

Three rings. Each is optional above the one below, and each is authoritative about a
different thing.

| Ring | Authoritative about | Needs the ring above? |
|---|---|---|
| **Machine view** | nothing — it reads the box and issues calls | no |
| **Placement** (intentions) | what was *asked for*, across N boxes | no |
| **Tenancy** (projects) | whose work it is | no |

- **Machine view** — one box, shaped by the role it reports. Stateless in the console: a
  deploy sends an AppConfig and keeps nothing.
- **Placement** — one app across several boxes: count, exposure, placements
  ([`one-primitive-composed.md`](one-primitive-composed.md)). A layer, not the spine, and
  its gap with reality is never closed automatically
  ([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)).
- **Tenancy** — ownership, sharing, grouping by client. A homelab never needs it.

They are separate: *"deploy app X to boxes A, B, C behind balancer L"* needs no client,
and *"Client Acme owns boxes A and B"* needs no apps.

## One app, with engines

**Rails engines** (`vilice-intentions`, `vilice-projects`): one process, one key store,
one record. Mount it or don't. The Rails app stays `vilice-console`; with no engines
mounted it is the machine view.

## The prerequisite: invert `App → Project` — done

An engine you can decline must be the thing that depends. `App.project` is optional, the
per-project name index is replaced by the per-machine rules `Placement` already enforced
(`app_name_free_on_machine`, `hostname_free_on_machine`), and apps live at `/apps`.

A project is optional context in the URL (`apps/new?project_id=`), not a form field: a
dropdown would put tenancy back in the middle of the flow.

**The test:** can you deploy an app to a box without creating a Project? Yes, both from
the machine view and through `App` with `project_id` null.

Unchanged: deleting a Project still destroys its apps, guarded by the refusal to delete a
project with a live placement. Whether a placement should survive its client is open in
[`open/install-journeys.md`](open/install-journeys.md).

## Why `ui-shape.md` does not foreclose this

[`ui-shape.md`](ui-shape.md) dropped the Operator/Dispatcher split, which was on **N** —
one machine versus many, the same screens with more rows. This splits on **domain**:
tenancy present or absent.

## Roads not taken

- **Two deployed Rails apps.** Two key stores, two record authorities, two surfaces to
  audit — against a design where one thing holds the keys. Both would need `Machine`, the
  SSH transport and auth, so the split would run through the shared half. And an operator
  who picks up a client should mount an engine, not migrate products.
- **An engine shipped by the box-side layer.** Couples a Go binary's release to a Rails
  one. Build it once concretely and let a second case say what is general.
- **Calling the engines "packs."** That word meant on-box, digest-pinned and
  root-authorized. An engine runs in the control plane and is none of those.
- **Renaming the Rails app** so "Console" meant the machine view alone. Console with
  nothing mounted already is the machine view.
- **Naming the layers as products** (Manor, Grounds, Orangery). If a reader needs the
  docs to decode a name, the name failed.

## Built and pending

| Piece | State |
|---|---|
| Machine view, stateless deploy | built |
| Drift as a surfaced gap (`App#count`, `placement_gap`) | built |
| `App.project` inversion, apps at `/apps` | built |
| Exposure, and the balancer (`vilice route`) | built |
| `Machine → Project` inversion | **pending** |
| `vilice-intentions`, `vilice-projects` engines | **pending** |

**Tenancy's own prerequisite.** `Machine` still depends on `Project` (`owner`,
`has_many :projects`, `granted_projects`, `permits?`, `ProjectMachine`, `MachineGrant`),
so the class will not load without it. Cut that first; only then is mounting a packaging
question.
