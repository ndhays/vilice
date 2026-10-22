# The VPN is not a control path

> Decided 2026-08-06. **Not built.** The shape is settled so it is not designed under
> deadline; the trigger is at the bottom. Extends
> [`provider-boundary.md`](provider-boundary.md).

## The decision

A private network may carry traffic between apps. It may never carry the operator.

| Path | Carries | Mechanism | Properties |
|---|---|---|---|
| **Control** | the operator, the console, any named actor | scoped SSH, `-J` through the jump box | named, scoped, recorded |
| **Data** | app → app | WireGuard between Vilice boxes | fast, always on, **carries no authority** |

> **The VPN is never a control path.** Nothing gains the ability to *act* on a box by
> being on the network.

An app talking to Postgres is a program using a network. It needs no named actor and
writes no record.

## Why a VPN cannot be the control path

- **Standing reachability, below the gate.** ProxyJump is one TCP connection to one
  destination the jump box permits (`permitopen`), forwarded by a box that cannot read
  it. A WireGuard peer can reach every port on every peer, and only firewall
  configuration stands in the way. The boundary turns from the absence of paths into a
  rule saying don't ([`no-key-gets-a-shell.md`](no-key-gets-a-shell.md)).
- **A second rights ledger.** `authorized_keys` is the ledger: named, scoped, readable.
  `wg show` would be a second answer to "who can act here", with no actor names, scopes
  or record entries.
- **A broken data path must never lock you out.** If the VPN carried operator access, a
  bad peer table would cut reach to every box at once. With the paths separate, you SSH
  in and repair it. This decides it even if the security argument were a wash.
- **Two barriers.** Compromising the mesh yields app-level network reach, not the ability
  to act on a box.

## The mechanism

> **sshd does not listen on `wg0`.**

Bind sshd to the public interface, or `ufw deny in on wg0 to any port 22`.
`harden --check` can verify it beside its sshd and ufw checks.

## The shape when it lands

| | Balancer | Mesh |
|---|---|---|
| Derived from | the apps that select this balancer | the Machines on the mesh |
| Sent as | routing table on stdin | peer table on stdin |
| Applied by | `vilice route` | `vilice peers` |
| Converges on its own | never | never |

**Key custody improves.** The box generates its own WireGuard keypair and reports only
the public key. The console never holds private material.

## What it costs

- Two network paths to reason about.
- A second keyring. Peers are boxes, already named as `Machine` rows, but `wg show` will
  not appear on the Access page.
- Mesh config is a new thing that can be wrong.

## Roads not taken

- **WireGuard for everything, control included.** Collapses two barriers into one and
  makes a network mistake a fleet-wide lockout.
- **No VPN; ProxyJump forever.** Right for operator access. Does nothing for app-to-app.
- **Cloud-provider private networks** (Hetzner vSwitch). Provider-specific. Fine as an
  extra an operator chooses.
- **Peers as people** — a WireGuard config for an operator. An unnamed, unscoped,
  unrecorded actor with standing network access.

## Still open

**The trigger: an accessory on its own box.** Until then there is no app-to-app traffic
across boxes. Weaker triggers: the jump box proving a real single point of failure, or a
fleet no provider network spans.

Unanswered until then: how the mesh shows on the Access page; whether `vilice peers` is
one verb or add/remove; what happens to a box's peers when it is removed from the
console.
