# Steward Console — Core Patterns & Boundaries

> The handful of patterns the whole system composes from, and the boundaries that keep
> each piece doing one thing. Read this to understand *what Steward Console is responsible for*
> — and, just as importantly, what it deliberately is not.

**Status:** Canonical **model**. The model is settled; implementation is staged. **Built:**
AppConfig (the deploy spec), the Install binding incl. count and exposure, multi-placement,
and the self-hosted Balancer. **Settled but pending:** MachineSpec + ProviderAdapter
(provisioning), the managed-LB realization, rollout orchestration, and the private-network
jump. The *why* and roads not taken are
in [`one-primitive-composed.md`](../../decisions/one-primitive-composed.md) and
[`provider-boundary.md`](../../decisions/provider-boundary.md). Last touched 2026-06-24.

---

## Two programs, two purposes

- **Steward — the accountable gate on one box.** It turns a scoped SSH request from a named
  actor into a recorded, bounded action on *that box*, which keeps its own tamper-evident
  record. Daemonless, no caller-root, **app-agnostic, fleet-agnostic, provider-agnostic.**
  It does not know other boxes exist. *One box, one gate, one record.*
- **Steward Console — the accountable control plane across boxes.** It lets an operator (or
  agent) express intent and act on a fleet, composing the per-box gates into one scoped,
  witnessed, recorded view. It does not provision, route traffic, or run containers — it
  **orchestrates and records.**

Together: **accountability that composes from one box to a fleet.** Everything below is in
service of keeping that true — and keeping the deep, solved problems (compute, networking,
TLS, containers) *borrowed*, not rebuilt ([`borrowed-substrate.md`](../../decisions/borrowed-substrate.md)).

## The composition

Three scale-free, provider-free **units**, one thing that **binds** them, and two
**realization adapters**:

```
AppConfig ──────┐                      "what runs" — one app instance
                │
MachineSpec ─┐  ├──► Install ──► InstallTarget(s) ──► Machine(s)
  (a box      │  │   the BINDING:        one per box        ▲
   request)   │  │   • count                                │ realized by:
            realizes│• exposure (edge | balancer)    ┌──────┴────────┐
              via   │• source (existing | new)   existing box   MachineSpec
            Provider│                                          + Provider (new)
                    └─ exposure=balancer ─► Balancer ─► (Caddy Machine | managed LB)
```

## The patterns

### AppConfig — what an app *is* when running
The desired runtime state of **one app instance**: hostnames, env (non-secret), secrets
(names here, values off-record), volume *declaration*, port, health. Separated from the
**code** (the image digest) so "update the code" and "change the config" stay distinct,
separately-witnessed acts. It is Twelve-Factor's *Config*. Steward converges one box to it
(`appState` on the box; `Install#deploy_envelope` builds it). See
[`../../decisions/open/deploy-config-model.md`](../../decisions/open/deploy-config-model.md).

**AppConfig is a first-class, self-versioned artifact** (decided 2026-06-24) — addressed by its
own digest, where editing mints a new version and the slot (`Install` / `apps/<name>` on the box)
holds a *timeline* of them, one current. This is the grain rollback, restore, drift, and "adopt
what the box runs" all compose from, and it is distinct from the App Library's `Version` (which
versions *code*). The artifact is the unit; the box owns reality, Steward Console owns desire, drift is
digest ≠ digest. See [`../../decisions/app-config-is-the-artifact.md`](../../decisions/app-config-is-the-artifact.md).
*(Principle settled; the version table / box history layout is staged.)*

**AppConfig is scale-free by construction.** Steward only ever converges *one* box to *one*
AppConfig — it has no concept of "how many." So replicating an app is deploying the same
AppConfig to N boxes; the count lives on the Install, never here. The single scale-related
fact AppConfig carries is **replicable?** — effectively *stateless / no volume*. That's a
property of the unit (it *gates* whether the Install may set count > 1), not a count.

### MachineSpec — what kind of box
A **box request**: size (normalized t-shirt sizes), region, role (`app` | `balancer`).
Provider-free in shape; each Provider maps it to its own SKUs and resources. Consumed at
birth/resize and recorded on the resulting Machine for later lifecycle. The machine-side
parallel to AppConfig. *(Pending — arrives with the first ProviderAdapter.)*

### ProviderAdapter — births, kills, resizes substrate
On request, makes a box **reachable-and-Steward-ready** and returns the four facts (below);
optionally tears it down, resizes it, or provisions a managed LB. **Hetzner first; the core
needs none.** Once a box is Steward-ready the Provider is irrelevant to *operation* — every
deploy/observe/record runs over SSH and never touches it again, until birth/death/resize. So
the Provider is a birth-death-resize concern, not an operation concern, and a hand-registered
bare-SSH box (no Provider) works fully — that is the capture-resistance guarantee. *(Pending.)*

### Install — the binding (where scale, exposure, and source live)
Takes one AppConfig and lands it on substrate as **InstallTarget(s)** — one per box. It
carries the three things the units don't:
- **count** — 1, or N (only when the AppConfig is replicable);
- **exposure** — *On the Edge* (public, count 1) or *Behind a Balancer* (private, count 1…N);
- **source** — *existing* boxes (pick) or *new* (MachineSpec → Provider).

App lifecycle acts across *several* boxes happen here, per target — the Install is the
app-actions home for placement
([`install-the-app-actions-home.md`](../../decisions/install-the-app-actions-home.md)).

The **machine view** has the same verbs for *one* box, with no Install and no Project:
the config is sent and discarded, and the box's record is the only record. They are two
layers rather than two doors — see that decision's "What changed".

### Balancer — the (optional) shared public edge
A routing entity: a **public endpoint** plus a **routing table reconciled from the installs
behind it**. It is a *role over Machine*, not a new primitive, realized two ways:

| Realization | What it is | Reconciled via | Recorded in |
|---|---|---|---|
| **Self-hosted** | Caddy on a box → a **Machine** (`role: balancer`) | SSH + Steward | the box-witnessed record |
| **Managed** | a provider LB (e.g. Hetzner) — **no SSH, no Steward** | the Provider API | Steward Console's *authored* record |

Ownership/sharing is the **Machine model unchanged** ([`machine-ownership.md`](../../decisions/machine-ownership.md)):
dedicated to one project by default (isolation preserved), shareable to a list ("owned by
Steward Console, usable by selected projects" = *unowned + sharing=list*). The self-hosted Caddy
balancer is the provider-agnostic default and **doubles as the bastion** (next section); the
managed LB is the opt-out for bought HA, and lives outside the SSH/record spine.

**Self-hosted is built** (2026-08-03). `Machine#balancer` is the role, the table is derived
by `RoutingTable` from the installs that select it, and applying it is the `route` act —
`steward route` writing a second Caddy fragment on the box. "Reconciled from the installs
behind it" means *derived on read*, not converged in the background: the table is computed
when it is shown and when it is sent, and a person presses Apply
([`drift-is-surfaced-never-closed.md`](../../decisions/drift-is-surfaced-never-closed.md)).
The managed-LB realization is still pending.

## The boundary: what Steward Console must know — and must not care about

To do its one job, Steward Console needs exactly **four facts** about a machine, all
provider-agnostic — and they are the columns `Machine` already has:

1. **how to reach it** — an SSH endpoint (host + port);
2. **how to be authorized on it** — its scoped key;
3. **who it is** — a stable identity (machine-id), to tie the record to;
4. **that the gate is live** — Steward answers.

It must **not** care about: how the box was created, its size/CPU/RAM as a *choice* (it
*observes* actual resources via Steward, never picks them), region, OS image, networking,
firewalls, snapshots, billing, the managed LB's internals, or how the box is destroyed. All
of that is behind the Provider. For lifecycle only, a Machine may also hold a thin, **nullable
provider linkage** (provider name + resource id + the MachineSpec it was born from); null = a
box you registered and manage yourself.

## Private networks: SSH `ProxyJump`, not a new control path

A backend with no public IP is reached by **jumping through a public box** — `ssh -J <jump>
<backend>`. The jump is end-to-end: the jump box forwards raw TCP, can't read the session,
and the scoped key still authenticates to the *backend's* Steward — so the forced command and
the record still happen on the backend. **Accountability is preserved; the jump box records
nothing.** The self-hosted Caddy balancer *is* that public box, so it serves as both the
traffic edge and the SSH bastion; backends stay fully private. Mechanically a backend Machine
gains an optional `via: <jump machine>` and the transport adds `-J`; the jump box carries a
narrow forwarding-only affordance (`permitopen` to the backend subnet), separate from its
Steward gate. *(Pending — lands with Balancer/fleet.)*

Rejected alternatives (see [`provider-boundary.md`](../../decisions/provider-boundary.md)):
the jump box becoming a sub-Steward Console (a privileged second recorder), and boxes *streaming*
their state out (the daemon/push model Steward rejects — fine for future *observe*, wrong for
witnessed *mutate*).

## Built vs. pending

| Piece | State |
|---|---|
| AppConfig (deploy spec, env/secret/volume/health) | **built** |
| Install binding — single placement, **existing** box | **built** |
| Observe reconciliation (reality vs plan) | **built** |
| Intention (`Install#count`) + placement gap, surfaced never closed | **built** |
| Closing a gap as an act (`POST /installs/:id/targets`) | **built** |
| Restating the intention (`count`/`exposure`), touching no box | **built** |
| `replicable?` gate — stateless-only replication, derived from volumes | **built** |
| Exposure (On the Edge vs Behind a Balancer) as the gate on count | **built** |
| Install UI placement step | Box × Exposure × scale, minus the managed balancer |
| MachineSpec + ProviderAdapter (provisioning, "New Box") | settled, **pending** |
| AppConfig as a versioned artifact (digest identity + slot timeline) | principle settled, **pending** |
| Accessories (linked Redis/Postgres) — `accessories` block in the AppConfig | in scope, **pending** |
| Balancer — role over Machine, derived table, applied as an act | **built** |
| Rollout orchestration across a balanced install's targets | **pending** |
| Private-network jump (`via` / ProxyJump) | settled, **pending** |
| Managed cloud LB (out-of-spine) | settled, **pending** |

**Beta needs none of the pending rows.** Beta is the accountability membrane over
hand-registered boxes; provisioning, fleet, and balancers layer onto these boundaries
without reshaping them.
