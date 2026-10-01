# The provider boundary — own the accountability, borrow the infrastructure

> Decided 2026-06-18. The line between Vilice Console and the cloud. Extends
> [`borrowed-substrate.md`](borrowed-substrate.md) down to the provider, and pairs with
> [`one-primitive-composed.md`](one-primitive-composed.md). The canonical *what* is
> [`../blueprint/console/patterns.md`](../blueprint/console/patterns.md); this is the
> *why* and the roads not taken.

## The problem

A "Create Machine" flow that picks sizes, regions, volumes, firewalls, and load balancers is
**rebuilding the Hetzner console, worse.** The providers have solved provisioning,
networking, volumes, LBs, and HA with far more capital than we have. The question isn't *how
do we build that* — it's *what is the smallest thing Vilice Console must know so the provider is
replaceable and mostly invisible.*

## The decision

**Vilice Console owns the accountability layer; the provider owns the infrastructure.** Concretely:

- **Vilice Console needs four facts** about any machine — *how to reach it* (SSH endpoint), *how
  to be authorized on it* (its scoped key), *who it is* (machine-id), and *that the gate is
  live* (Vilice answers). These are provider-agnostic and are the columns `Machine` already
  has.
- **A ProviderAdapter** births/kills/resizes substrate and returns those facts. Hetzner
  first. The interface is roughly `provision(MachineSpec) → facts`, `teardown`, `resize`,
  and (capability) a managed LB.
- **Once a box is Vilice-ready, the provider is irrelevant to operation.** Every deploy,
  observe, scope-check, and record entry runs over SSH; the provider is touched only at
  birth/death/resize. So the Provider is a *lifecycle* adapter, not an *operation* dependency.
- **The linkage is thin and nullable.** A Machine may carry `provider` + `provider_resource_id`
  + the `MachineSpec` it was born from, used *only* for lifecycle. Null = a hand-registered
  bare-SSH box you manage yourself.

## Why this is the right cut

- **It keeps both programs one-thing-well.** Vilice stays the gate on one box; Vilice Console
  stays the accountable control plane across boxes. Neither grows an infrastructure brain.
- **It is the capture-resistance guarantee, made concrete.** Rip out every adapter and
  Vilice Console still operates every box you can SSH. The provider is favored substrate, not a
  dependency; bare SSH is the floor.
- **It mirrors the app side exactly.** AppConfig : Vilice :: MachineSpec : Provider — two
  declarative specs, two reconcilers, the same Boxcar grain. (This symmetry is why a reusable
  *"accountable, provider-agnostic provisioning"* Boxcar engine could later fall out — noted,
  not built.)

## Load balancers: in-spine Caddy vs. managed appliance

An LB is **not a new Vilice feature** — it is Caddy deployed by Vilice like any other app
(a Caddy AppConfig whose config *is* the routing table). Two realizations:

- **Self-hosted Caddy balancer** — a Machine (`role: balancer`). In the SSH/record spine,
  provider-agnostic (the same box on any cloud), and it doubles as the **bastion** for private
  backends. The default.
- **Managed cloud LB** (Hetzner/Vultr) — a closed appliance: **no SSH, no Vilice.** It can't
  enter the spine and can't be a bastion; Vilice Console configures it via the Provider API and
  records the act in its *own* authored record (consistent with two-records, where provisioning
  was always authored, not box-witnessed). The opt-out for bought HA.

You **cannot SSH a managed cloud LB** — that's why it lives outside the spine. If you want the
edge inside your accountable spine, it must be a box you own.

## Private networks: jump, don't re-architect

A private backend (no public IP) is reached by `ssh -J <jump> <backend>`. The jump is
end-to-end — the jump box forwards raw TCP, can't read the session, and the scoped key still
authenticates to the *backend's* Vilice, so the forced command and the record stay on the
backend. The self-hosted balancer is the jump box. A backend Machine gains an optional
`via:`; the jump box carries a narrow forwarding-only key (`permitopen` to the backend
subnet), distinct from its Vilice gate.

This covers the **operator**. It does not cover **app-to-app** traffic in general, which
still has no path. One case is closed: an app may declare **accessories** — a database, a
cache — on a network only that app joins, so `web → db` never becomes `anything → db`
([`accessories-belong-to-one-app.md`](accessories-belong-to-one-app.md)). That is
deliberately the narrow case, one app reaching what belongs to it. Two apps talking to each
other, a shared cache, or an accessory on its own box are all still unaddressed — and when
one lands, the answer is a private network carrying data only, never the operator:
[`the-vpn-is-not-a-control-path.md`](the-vpn-is-not-a-control-path.md).

## Roads not taken

- **Build provisioning/LB/volumes/firewalls ourselves.** Rejected — that is the Hetzner
  console, rebuilt worse, and it spends our budget on solved problems instead of the
  accountability nobody else sells.
- **The jump box as a sub-Vilice Console** (SSHes its backends, re-records, reports up). Rejected:
  a privileged intermediary holding every backend's keys and a *second recorder* — against the
  small-legible-ceiling and two-records. ProxyJump gets the reachability with the jump box
  holding and recording nothing.
- **Boxes stream their internals out** (push/daemon). Rejected for *mutate*: it inverts
  accountability (a box pulling work has no named actor who authorized it) and is the daemon
  model Vilice refuses. Fine as a *future observe* optimization, not a control path.
- **A fat Machine record mirroring provider state** (sizes, networks, billing). Rejected: we
  store the four facts + a nullable lifecycle handle; actual resources are *observed* via
  Vilice, never configured or mirrored.
