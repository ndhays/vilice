# The provider boundary — own the accountability, borrow the infrastructure

> Decided 2026-06-18. Extends [`borrowed-substrate.md`](borrowed-substrate.md) to the
> cloud provider. Spec: [`../blueprint/console/patterns.md`](../blueprint/console/patterns.md).

## The decision

**The console owns the accountability layer; the provider owns the infrastructure.** A
Create Machine flow that picks sizes, regions, volumes and firewalls is the provider's
console, rebuilt worse.

- **The console needs four facts** about a machine: how to reach it (SSH endpoint), how to
  be authorized on it (its scoped key), who it is (machine-id), and that the gate is live
  (Vilice answers). `Machine` already has these columns.
- **A ProviderAdapter** creates, destroys and resizes substrate and returns those facts.
  Hetzner first.
- **Once a box is Vilice-ready, the provider does not matter to operation.** Every deploy,
  read and record entry runs over SSH. The provider is a lifecycle adapter.
- **The link is thin and nullable:** `provider`, `provider_resource_id`, and the
  `MachineSpec` it was born from. Null means a hand-registered box.

Remove every adapter and the console still operates every box you can SSH. Bare SSH is
the floor.

## Load balancers

An LB is Caddy deployed by Vilice, not a new feature. Two forms:

- **Self-hosted Caddy balancer** — a Machine with the balancer role. Inside the SSH and
  record spine, provider-agnostic, and it doubles as the jump box for private backends.
  The default.
- **Managed cloud LB** — a closed appliance with no SSH and no Vilice. The console
  configures it through the provider API and records the act in its own record. The
  opt-out for bought HA.

## Private networks: jump, don't re-architect

A backend with no public IP is reached by `ssh -J <jump> <backend>`. The jump box forwards
raw TCP and cannot read the session; the scoped key still authenticates to the backend's
Vilice, so the forced command and the record stay on the backend. A backend Machine gains
an optional `via:`. The jump box carries a narrow forwarding-only key (`permitopen` to the
backend subnet), separate from its Vilice gate.

This covers the operator. App-to-app traffic in general still has no path. The on-box
case is closed by accessories
([`accessories-belong-to-one-app.md`](accessories-belong-to-one-app.md)). The rest, when
it lands, is a private network carrying data only, never the operator
([`the-vpn-is-not-a-control-path.md`](the-vpn-is-not-a-control-path.md)).

## Roads not taken

- **Build provisioning, LBs, volumes and firewalls ourselves.** Spends the budget on
  solved problems.
- **The jump box as a sub-console** that SSHes its backends and reports up. A privileged
  intermediary holding every backend's keys, and a second recorder. ProxyJump gives the
  reach with the jump box holding and recording nothing.
- **Boxes push their state out** (a daemon). For mutate it inverts accountability: a box
  pulling work has no named actor who authorized it. Possible later for observe only.
- **A fat Machine record mirroring provider state** (sizes, networks, billing). Resources
  are observed through Vilice, never mirrored.
