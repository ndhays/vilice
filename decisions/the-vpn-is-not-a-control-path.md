# The VPN is not a control path

> Decided 2026-08-06. A private network may carry traffic **between apps**; it may never
> carry the operator. Extends [`provider-boundary.md`](provider-boundary.md), which settled
> operator access to private backends (`ProxyJump`) and left app-to-app traffic unanswered.
> Follows the same rule as [`orchestrators-are-clients.md`](orchestrators-are-clients.md):
> the ways in stay countable.
>
> **Not yet built**, and deliberately — the trigger is named at the bottom. What is settled
> is the *shape*, so that when it is built it is not designed under deadline.

## The question

A backend with no public IP has to be reachable. [`provider-boundary.md`](provider-boundary.md)
answered that for the **operator**: `ssh -J <jump> <backend>`, where the jump is end-to-end,
the jump box forwards raw TCP and cannot read the session, and the scoped key still
authenticates to the backend's own Vilice — so the forced command and the record stay on
the backend, and the jump box holds and records nothing.

It did not answer **app-to-app**. Today that does not matter: an app is one container plus
volumes, and the only cross-box traffic is balancer → backend HTTP. The moment an accessory
(Postgres, Redis) lands on its own box, an app on box A needs box B, and ProxyJump does
nothing for it — it is an operator-access mechanism, not a data path.

WireGuard is the obvious answer, and a good one: small, fast, in-kernel, provider-agnostic,
and exactly the sort of deeply-solved problem [`borrowed-substrate.md`](borrowed-substrate.md)
says to borrow rather than rebuild. So the real question is not whether to use it. It is
whether to use it for *everything*.

## The decision

**Two paths, and the separation is the point.**

| Path | Carries | Mechanism | Properties |
|---|---|---|---|
| **Control** | the operator, the console, any named actor | scoped SSH, `-J` via the jump box | named, scoped, recorded, un-bypassable |
| **Data** | app → app | WireGuard between Vilice boxes | fast, always-on, **carries no authority** |

And the rule that makes it hold:

> **The VPN is never a control path.** Nothing gains the ability to *act* on a box by being
> on the network.

An app talking to Postgres is not acting on a box; it is a program using a network. It needs
no named actor and writes no record, and pretending otherwise would make the record
meaningless by filling it with traffic. Operator access is the opposite in every respect.
They were never the same problem, so one mechanism for both was always going to be wrong for
one of them.

## Why a VPN cannot be the control path

**It grants standing reachability, below the layer the gate lives at.** ProxyJump is a
per-connection capability: one TCP connection, to one destination the jump box permits
(`permitopen`), forwarded by a box that cannot read it. Nothing accumulates. A WireGuard peer,
by contrast, can reach *every port on every peer* at the IP layer, and the only thing standing
in the way is firewall configuration.

That converts the boundary from **the absence of paths** into **a rule saying don't** — which
is the exact trade this project refuses everywhere else
([`no-key-gets-a-shell.md`](no-key-gets-a-shell.md)).

**And it would create a second rights ledger.** `authorized_keys` *is* the ledger: nameable,
scoped, `cat`-able, read straight off the box by the Access page precisely so there is never a
second answer to "who can act here". `wg show` would be that second answer — a list of public
keys with no actor names, no scopes, no chain entries, and nothing the Access page could
render.

## The argument that actually decides it

**A broken data path must never lock you out.**

If the VPN carried operator access, a bad peer table or a key rotation gone wrong would brick
reach to every box at once — the same class of failure as a firewall rule that assumes port 22,
but fleet-wide and simultaneous. With the paths separate, the control path does not depend on
the network you just broke: you SSH in and repair it.

This is operational rather than theoretical, and it is why the split is right even if the
security argument were a wash.

The security version of the same point: compromising the mesh yields app-level network reach
and **not** the ability to act on any box, because the gate still sits in front of every act.
Two independent barriers rather than one.

## The mechanism, named

A rule with no mechanism is commentary. This one is enforceable in configuration:

> **sshd does not listen on `wg0`.**

Bind sshd to the public interface, or `ufw deny in on wg0 to any port 22`. Then "the VPN is
not a control path" is a fact about the box rather than an intention, and — usefully —
`harden --check` can verify it alongside the sshd and ufw checks it already performs. It
becomes a posture fact that drifts, gets caught, and is reported.

## The shape it takes when it lands

The machinery already exists, because the balancer needed the same thing:

| | Balancer | Mesh |
|---|---|---|
| Derived from | the installs that select this balancer | the Machines on the mesh |
| Sent as | routing table on stdin | peer table on stdin |
| Applied by | `vilice route` | `vilice peers` |
| Converges on its own | never | never |

Derived on read, applied by a person, never reconciled in the background
([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)). One new verb,
reusing a pattern that is already built and tested.

**Key custody inverts, and improves.** For SSH the console generates the keypair and the box
authorizes the public half. For WireGuard the **box generates its own keypair and reports only
the public key** — private material never leaves the machine and the console never holds it.
Strictly better custody than the SSH model, and worth noting as a small win rather than a new
risk.

## What it costs

- **Two network paths** to reason about, document, and get right.
- **A second keyring** — narrower than it first appears, since peers are *boxes* rather than
  people, and boxes are already named `Machine` rows. But `wg show` still will not appear on
  the Access page, and that is a real gap in a surface whose pitch is completeness.
- **Mesh config is a new thing that can be wrong.** Mitigated, not removed, by the control
  path being independent of it.

## Roads not taken

- **WireGuard for everything, control included.** The tempting simplification: one network,
  one mechanism, private backends and operator access both solved. Rejected on both arguments
  above — it collapses two independent barriers into one, and it makes a network
  misconfiguration a fleet-wide lockout.
- **No VPN at all; ProxyJump forever.** Correct for operator access and the current answer.
  It does nothing for app-to-app, so it stops being sufficient the moment accessories get
  their own box.
- **Cloud-provider private networks** (Hetzner vSwitch and equivalents). They solve it with no
  new software, and they are provider-specific — against
  [`provider-boundary.md`](provider-boundary.md)'s insistence that a bare-SSH box on any
  substrate works fully. Fine as an *additional* option an operator chooses; not the answer.
- **Peers as people** — handing an operator a WireGuard config to reach the fleet. That is an
  unnamed, unscoped, unrecorded actor with standing network access, which is the whole thing
  this decision refuses.

## Still open

**Whether and when to build it. The trigger is specific: an accessory on its own box.** While
an app is one container plus volumes, there is no app-to-app traffic and a mesh would be
machinery in search of a use. Accessories are already in-scope-pending in
[`../blueprint/console/patterns.md`](../blueprint/console/patterns.md), so this is a *when*.

Secondary triggers, weaker: the jump box proving a real single point of failure in practice
rather than in theory, or a fleet spread across infrastructure no provider network spans.

Left unanswered until then: how the mesh appears on the Access page, if at all; whether
`vilice peers` is one verb or peer-add/peer-remove; and what happens to a box's peers when it
is removed from the console.
