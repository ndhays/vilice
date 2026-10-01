# The role belongs to the box

Why the console stopped offering "Make this a balancer", and what the stored
`balancer` column is for now.

## The question

A box is prepared as a `host` (runs apps) or a `balancer` (fronts others). The console
also carried a `Machine#balancer` boolean with a button to toggle it. Which one is the
role?

## The decision

**The box's.** `steward prepare <role>` writes `/var/lib/steward/role` once and
**refuses to convert** a prepared box into the other role — you take its apps off,
uninstall, and prepare again ([`blueprint/vilice/provision.md`](../blueprint/vilice/provision.md)).
`SetRole` enforces this, and it is deliberate: turning a host that is running apps into
a balancer by re-running one command is exactly the silent surprise this project avoids.

So the console has no opinion to offer. The button is gone. The role is reported.

## What was wrong with the button

It wrote a column with nothing behind it. Marking a `host` as a balancer did not
prepare anything: the box has no Caddy, and no amount of clicking gives it one. But the
console believed it — balanced installs could then select that box, and the routing act
would be refused *by the box*, at the end of the chain, after someone had built a
placement on the assumption.

It was also a control that implied a capability the system explicitly does not have.
Every other refusal in Steward is stated up front; this one was discovered late.

## What the column is for now

It stays, as **our mirror of the last read**. The fleet list cannot do a live SSH read
per row — that is the same constraint that blocks the reported-hostname column and
waits on ingestion (#6 in [`open/ui-roadmap.md`](open/ui-roadmap.md)) — so a stored
answer is the only way a list can group by fleet at all.

`Steward::Observe.reconcile` writes it, alongside the reachability and hostname it
already projects: a projection, not a witnessed act, so no Event and no callbacks
(the rule from [`a-sample-is-not-an-act.md`](a-sample-is-not-an-act.md)). A box that
reports **no** role leaves the column alone — a blank is *unknown*, not "host", and
quietly demoting a balancer we simply failed to ask would be the same class of error
in the other direction.

## Three states, kept apart

| What happened | Reads as |
|---|---|
| The box named a role | that role |
| We reached it, it named none | **not prepared** — and `steward prepare <role>` is the fix |
| We could not reach it | **unknown**, falling back to the last read we mirrored |

The middle row is the one worth having separately: "never prepared" is an actionable
state with a command attached, and folding it into "unknown" would hide that.

## Consequence

`machines#balancer` and its route are deleted, along with the toggle in the sharing
panel. `Steward::Observe.reconcile_role` writes the column. The fake-observe seam
reports a role too — without it every box in every seeded scenario read as "not
prepared", which is a state almost no real box is in.
