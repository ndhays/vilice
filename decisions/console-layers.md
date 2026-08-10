# The console is layered too — three rings, one app

> **Vocabulary note, 2026-08-10.** This doc argues in terms of *packs*, the plugin layer
> Steward had at the time. That layer is gone
> ([`roles-not-packs.md`](roles-not-packs.md)) — one binary, a trust core and an app
> layer, and the machine view is shaped by the box's **role** rather than by which packs
> it reports. Read "pack" below as "the app layer": every argument here survives the
> rename, including the one that matters most — *the console's engines are not that
> thing and must not be called it*, because they run in the control plane and are not
> digest-pinned on a box.
>
> Decided 2026-08-03. The console has the same seam the binary had before
> [`core-and-packs.md`](core-and-packs.md): a small generic layer fused to one domain's
> UI. Same call, one level up — draw the line, keep one deployable, split physically
> only when something real demands it.

## The question

Steward split into a core and verb packs, and the console did not follow. It is
currently three things wearing one name, and the fusion shows: **you cannot deploy an
app without first inventing a client.** `Install belongs_to :project`, required, with
install names unique per project and installs nested under projects in the routes.

That is not a console with a Projects feature. It is a Projects app with some console
views inside it.

## The decision

Three rings. **Each is optional above the one below, and each is authoritative about a
different thing** — which is why they don't collapse into "which one is right?"

| Ring | Authoritative about | Needs the ring above? |
|---|---|---|
| **Machine view** | nothing — it reads the box and issues calls | no |
| **Placement** (intentions) | what was *asked for*, across N boxes | no |
| **Tenancy** (projects) | whose work it is | no |

- **Machine view** — one box, shaped by what that box reports about itself (its role,
  since [`roles-not-packs.md`](roles-not-packs.md); the packs it ran, before that).
  Stateless in the console: a deploy sends an AppConfig and discards it, and the box's
  record is the only record. This is the floor, not a lens you rarely visit —
  [`install-the-app-actions-home.md`](install-the-app-actions-home.md) "What changed".
- **Placement** — one app across several boxes: count, exposure, targets. The model is
  settled in [`one-primitive-composed.md`](one-primitive-composed.md); what this decision
  adds is that it is a *layer*, not the spine, and that the gap between it and reality is
  never closed automatically
  ([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)).
- **Tenancy** — ownership, sharing, grouping by client. A homelab never needs it; an
  agency needs it on day one.

Evidence they are genuinely separate: *"deploy app X to boxes A, B, C behind balancer L"*
is coherent with no client anywhere. *"Client Acme owns boxes A and B"* is coherent with
no installs. Today's schema welds the second to the first for no reason but history.

Worth noting that **tenancy has no unix analogue at all.** A machine view is `cockpit`;
placement is what Ansible does — desired state driven from a client with no agent on the
box. Tenancy is business bookkeeping. That absence is the argument for it being the
outermost, most optional ring.

## One app, engines — not two apps, and not packs

**Not two deployed Rails apps.** Two apps means two key stores, two record authorities,
two surfaces to audit — against the grain of a design whose point is that exactly one
thing holds the keys. Both would also need `Machine`, the SSH transport, and auth, so the
split would run *through* the shared half rather than along a seam.

**Rails engines**, which is Rails' own idiom for this and therefore the standard tool in
its native idiom. One process, one key store, one record. Mount it or don't:

```
on the box    steward-app,        steward-backup      (packs)
in the web    steward-intentions, steward-projects    (engines)
```

Same prefix and the same "named for what it promises" rule; the only difference is where
it runs.

**They are not packs, and must not be called packs.** A pack is on-box, digest-pinned,
root-authorized, and named in the chain. A Rails engine is none of those. Reusing the
word would cost the one word that currently means something precise.

**The Rails app stays `steward-console`** — one deployable, one name, exactly like the
binary. Console with no engines mounted *is* the machine view, so "Console is the machine
view" is true without renaming anything. One name you never have to defend is worth more
than three you do.

## The prerequisite: invert `Install → Project` — done

An engine you can decline has to be the thing that *depends*, not the thing depended on.
While `Install` requires `Project`, tenancy is load-bearing and no amount of file-moving
makes it optional.

The inversion was nearly free, because the constraint that actually matters was already in
the right place — `InstallTarget` enforces `install_name_free_on_machine` and
`hostname_free_on_machine`, which is uniqueness *on the box*, independent of any project.
So `Install.project` is optional, the per-project name index is gone in favour of the
per-machine rule that already existed, and installs have their own home at `/installs`
with a nav entry between Machines and Record.

A project is now **optional context in the URL** (`installs/new?project_id=`), the shape
`machines/new` already used — with one, the machine list narrows to that project's boxes;
with none, the whole operate-scoped fleet is offered. It is deliberately not a form field:
a dropdown would put tenancy back in the middle of the flow, one step short of requiring it.

The acceptance test is one sentence: **can you deploy an app to a box without creating a
Project?** Yes, both ways now — the machine view sidesteps `Install` entirely, and
placement goes through `Install` with `project_id` null, into the same witnessed ceremony.

What the inversion did **not** change: deleting a Project still destroys its installs
(`dependent: :destroy`), guarded by the refusal to delete a project with any live target.
Whether a placement should instead *survive* its client, becoming untenanted, is left
open — see [`open/install-journeys.md`](open/install-journeys.md).

## Why `ui-shape.md` does not foreclose this

[`ui-shape.md`](ui-shape.md) records that the "Operator vs Dispatcher" split was dropped,
and someone will cite it against this. It does not apply. That split was on **N** — a
single-machine UI versus a fleet UI, which turned out to be the same screens with more
rows, a lens difference and nothing more.

This splits on **domain**: tenancy present or absent. Different axis. The old rejection
stands on its own terms and this decision does not disturb it.

## Roads not taken

- **A second Rails app** ("Steward Projects" as its own deployable). Above: two key
  stores, two record authorities, and the split runs through the shared half. It also
  creates a migration cliff — an operator who starts with two boxes and picks up a client
  should mount an engine, not migrate to a different product.
- **An engine per pack** (`steward-app` ships its own Rails engine). Rejected for now on
  the same rule as the packs themselves: build it concretely once, and let a real second
  case say what is general. A pack is a Go binary on a box; making it also ship Rails
  would couple two very different release surfaces.
- **Calling the engines "console packs."** Rejected: see above. One word, one meaning.
- **Renaming the Rails app** so "Console" could belong to the machine view alone.
  Unnecessary once the layering is right — Console with nothing mounted already *is* the
  machine view — and it would cost a rename to buy a distinction the architecture already
  makes.
- **Naming the layers as products** (Manor, Grounds, Orangery were all considered).
  Rejected by the project's own naming rule: if a reader needs the docs to decode a name,
  the name failed. That is why Switchyard was retired, and re-buying the problem one
  month later would be hard to explain. "Intention" survives the test because it says
  what it is and, usefully, does *not* claim to be reality.

## Built vs pending

| Piece | State |
|---|---|
| Machine view, shaped by what the box reports, stateless deploy | **built** |
| `steward status` (role) / `actors` — the box's own facts, read live | **built** (`steward packs` existed here until the pack layer was dropped) |
| Drift as a surfaced, never-closed gap | **built** — `Install#count`, `placement_gap`, and the act that closes it |
| `Install.project` inversion, installs at `/installs` | **built** — the prerequisite |
| Exposure — the gate that makes a count above 1 honest | **built** |
| Balancer — the managed front edge those N boxes sit behind | **built** — `steward route` + the derived table |
| `Machine → Project` inversion | **pending** — tenancy's own prerequisite, see below |
| `steward-intentions` engine | **pending** — the layer works; extracting it does not block anything |
| `steward-projects` engine | **pending** |

## Tenancy has a prerequisite too, and it is not packaging

`Install` no longer depends on `Project`, but **`Machine` still does** — `belongs_to :owner,
class_name: "Project"`, `has_many :projects`, `granted_projects`, `permits?(project)`, plus
`ProjectMachine` and `MachineGrant`, which are entirely Project-shaped.

So the console cannot currently be run with tenancy declined: not because a machine needs an
owner (`owner` is already optional), but because the `Machine` class will not load without
the `Project` constant. The floor depends on the outermost ring, which is exactly the
inversion this decision says each ring must not require.

That makes `steward-projects` **not** an extraction job yet. The order is: cut `Machine`'s
dependence on `Project` first — the same move already made for `Install`, one layer down and
harder, because ownership and sharing are genuinely tenancy concepts that currently live on
`Machine` — and only then is mounting-or-not a packaging question.
