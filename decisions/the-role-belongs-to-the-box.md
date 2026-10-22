# The role belongs to the box

> Spec: [`blueprint/vilice/provision.md`](../blueprint/vilice/provision.md).

## The decision

A box's role is the box's. `vilice prepare <role>` writes `/var/lib/vilice/role` once and
**refuses to convert** a prepared box: take its apps off, uninstall, prepare again
(`SetRole`). The console reports the role. Its "Make this a balancer" button is gone.

## What was wrong with the button

It wrote a `Machine#balancer` column with nothing behind it. Marking a `host` as a
balancer installed no Caddy, but the console believed it: balanced apps could select that
box, and the routing act was refused by the box at the end, after someone had built a
placement on it.

## What the column is for now

It is **the mirror of the last read**. The fleet list cannot do an SSH read per row, so a
stored answer is the only way a list can group by it.
`Vilice::Observe.reconcile_role` writes it — a projection, so no `Event`
([`a-sample-is-not-an-act.md`](a-sample-is-not-an-act.md)). A box that reports no role
leaves the column alone: blank is unknown, not "host".

## Three states, kept apart

| What happened | Reads as |
|---|---|
| The box named a role | that role |
| We reached it, it named none | **not prepared** — `vilice prepare <role>` is the fix |
| We could not reach it | **unknown**, falling back to the last read |

"Not prepared" has a command attached; folding it into "unknown" would hide that.

`machines#balancer` and its route are deleted. The fake-observe seam reports a role too.
