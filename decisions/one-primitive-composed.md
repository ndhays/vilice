# One primitive, composed — App is intent, the gap is shown

> Decided 2026-06-17. The model for App / Machine / balancer. Spec:
> [`../blueprint/console/patterns.md`](../blueprint/console/patterns.md). Related:
> [`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md) (nothing
> converges on its own), [`console-layers.md`](console-layers.md) (the layering),
> [`provider-boundary.md`](provider-boundary.md) (the cloud line). Build detail stays in
> [`open/console-open-questions.md`](open/console-open-questions.md) and
> [`open/install-journeys.md`](open/install-journeys.md).

## The frame

`deploy` is a declarative upsert on one box
([declarative-deploy.md](declarative-deploy.md)). Extend it one level: an `App` is desired
state for a slice of the fleet. You author intent; the gap with reality is shown; closing
it is an act — named, scoped, recorded.

## The nouns

| Noun | Is | Role |
|---|---|---|
| **App** | the intent — the full spec (`App#deploy_envelope`), plus *how many* and *where* | what the operator manages |
| **Machine** | the authority and substrate — a scoped key pointed at a box | the floor |
| **Placement** | where intent meets substrate | carries plan vs. reality per box |
| **Balancer** | a Machine in the balancer role | the optional shared public edge |

**Machine is the floor.** It is invariant 1 made physical: a named actor with a declared
scope is the box's scoped key. The machine view can deploy to a box with no Project and
no plan. Intent leads for placement across boxes; it is not a prerequisite for using a
box.

Neither App nor Machine comes first. In the app flow, "where it runs" is a step inside
the App: pick an existing box, or declare a new one
([machine-onboarding.md](machine-onboarding.md)).

## Fleet is not a noun — exposure is

An App has an **exposure**, and when balanced, a **count**.

- **On the edge (public).** The box faces the internet and terminates its own TLS. Count
  is 1.
- **Behind a balancer (private).** DNS points at the balancer; the box can be private.
  Count 1…N is more upstreams.

Exposure is `edge` | `balanced` (default `edge`) and gates `count` at validation: without
it, an edge app could ask for three boxes all claiming one hostname. Restating it is a
recorded `restated intention` act that reaches no box. Picking a balancer is optional even
when balanced, for an operator running their own edge.

**Transitions.** An app that starts behind a balancer never touches DNS when it scales.
The only cutover is the one-time edge → balanced move. Anything you might scale starts
behind a balancer.

## The balancer

A balancer is a Machine with the balancer role, running a Caddy whose **routing table is
derived, not hand-written**, from the apps that select it.

- `Machine#balancer` is a boolean — no new table, because a parallel model would duplicate
  address, key, scope and ownership.
- `RoutingTable` derives the table; applying it is the `route` act (`vilice route`,
  [`../blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md)).
- **Derived on read, not converged in the background.** A person presses Apply.
- **Only boxes actually serving are upstreams.** Routing to a placed-but-not-running box
  would turn a visible gap into a 502.
- Ownership and sharing are the Machine model unchanged
  ([machine-ownership.md](machine-ownership.md)): dedicated to one project by default, or
  unowned with `sharing=list` to front several.

## Replication is stateless-only

A volume is data on one box's disk; N replicas are N diverging datasets. An app is
**replicable when it declares no volumes** — derived, not stored, because a stored flag is
a promise about the spec that can disagree with it. The gate is a validation: a stateful
app is refused a count above 1.

## Converging boxes is dangerous

Converging containers is cheap and reversible; converging boxes is not.

- **Provision** — un-witnessed setup with a live, resumable status.
- **Deploy** — witnessed (the ceremony).
- **Destroy** — witnessed, with friction, and it respects the in-use guard
  ([open/status-signals.md](open/status-signals.md)).

## Still open

Build, not model — all in
[`open/console-open-questions.md`](open/console-open-questions.md): cloud provisioning;
certificates on a shared balancer; private-backend networking; **HA for the balancer**
(two boxes and a floating IP — not v1); and the migrate verb, which is blue/green across
machines.

## Roads not taken

- **Fleet as a first-class object.** A second noun and a second scaling path for what is
  count + exposure.
- **An edge per fleet** (auto-create an LB when an app scales). Couples the edge to one
  app's lifecycle; DNS churns on every scale.
- **An invisible edge per project.** Superseded by the balancer: visible, manageable,
  optionally shared.
- **A load balancer as its own program.** It is Caddy on a Machine like everything else.
- **DNS round-robin.** Fails over slowly because clients cache DNS, and per-box TLS breaks
  — HTTP-01 challenges hit a random box.
- **In-box replicas** (N containers behind one box's Caddy). Bounded by one box and does
  not survive it.
- **Machine-first onboarding as the spine.** Kept as an alternate entry.
- **"The system converges substrate to match"** — an earlier draft of this decision.
  Wrong; see [`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md).
