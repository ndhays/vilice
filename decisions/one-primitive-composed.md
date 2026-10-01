# One primitive, composed — Install is intent, the fleet is reconciled

> Decided 2026-06-17. The simplification pass over the Install / Machine / Fleet /
> load-balancer model. Graduates and supersedes the framing scattered across
> [`open/console-open-questions.md`](open/console-open-questions.md) *(Replica /
> deploy strategy; Migrate an install)* and
> [`open/install-journeys.md`](open/install-journeys.md) *(Replicas / scale)* — those
> keep the **build** detail; the **model** is settled here. Extends
> [`declarative-deploy.md`](declarative-deploy.md) one level up. The canonical *what* now
> lives in [`../blueprint/console/patterns.md`](../blueprint/console/patterns.md); the
> Steward Console/cloud line is [`provider-boundary.md`](provider-boundary.md).
>
> **Revised 2026-08-03.** The model here is still the model — Install-as-intent, the
> three nouns, exposure instead of a Fleet object, Balancer-as-a-role, stateless-only
> replication. Two things were reversed by the core/pack layering
> ([`core-and-packs.md`](core-and-packs.md)): **nothing auto-converges**, and **the
> Machine is not demoted**. Both are corrected inline below; the reconciliation rule
> graduated to [`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md),
> and the layering it sits in is [`console-layers.md`](console-layers.md).

## The frame: declarative all the way up

Steward's `deploy` is a declarative upsert — *here is the full desired state, converge
the box to it* ([declarative-deploy.md](declarative-deploy.md)). The control-plane knot
(does Install or Machine come first? how does a fleet go 4→5?) comes from that thinking
stopping at the box. **Extend it:** an `Install` is desired state for a *slice of the
fleet*, and a reconciler closes the gap between that plan and what's actually running.

You author **intent**; the gap between it and reality is made visible, and closing that
gap is an **act** — named, scoped, recorded — not something the system does on its own.
That single move dissolves the rest.

**Nothing auto-converges.** An earlier draft of this decision said "the system converges
substrate to match," and that was wrong. The rule, and why it is the good property rather
than the compromise, is now its own decision:
[`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md).

## Three nouns, and what each is for

| Noun | Is | Role |
|---|---|---|
| **Install** | the **intent** — the full desired spec (`Install#deploy_envelope`), now incl. *how many* and *where* | the front door; what the operator manages |
| **Machine** | the **authority + substrate** — a scoped key, a scope, an owner, pointed at a box | a reconciled resource + the read-only box lens |
| **InstallTarget** | the **placement** — where intent meets substrate | carries plan-vs-reality *per box* |
| **Balancer** | a Machine in a **balancer role** — Caddy with a routing table reconciled from the installs behind it | the (optional) shared public edge; its own page (*see below*) |

The Balancer is the one addition — a *role over Machine*, not a fourth primitive (*"The
edge is a Balancer"*, below).

**Machine is not demoted — it is the floor.** It *is* Agora Invariant 1 made physical: a
named actor with a declared scope is the box's scoped SSH key. This decision originally
had it demoted to "a record of a box we're allowed onto, plus a lens," on the grounds
that intent leads and the machine page was read-only for apps. The core/pack split
reversed that: the machine view is the **base layer**, shaped by the packs a box reports,
and it can deploy to a box with no Project and no plan at all
([install-the-app-actions-home.md](install-the-app-actions-home.md), "What changed").

Intent still leads *for placement across boxes*. It is not a prerequisite for using a
box.

## The chicken-and-egg, dissolved

Neither Install nor Machine is a prerequisite. **Intent is authored first; substrate is
converged to match.** In the install flow, "where it runs" is a *step inside the Install*,
not a thing you build beforehand:

- **existing box** — pick one already on the project;
- **new box** — declare it; the reconciler provisions it (cloud-provider API, Hetzner
  first), installs Steward, authorizes the operate key, then deploys
  ([machine-onboarding.md](machine-onboarding.md)).

The Machines page still exists for pre-provisioning a bare box or browsing the lens — an
alternate entry that writes the *same* records, not the foundation.

## Fleet is not a noun — exposure is

There is no Fleet object and no "single vs fleet" mode. An Install has an **exposure**, and
when balanced, a **count**:

- **On the Edge (public).** The box faces the internet and terminates its own TLS; DNS
  points at the box. Count is **1** — one box, one IP (scaling here would need round-robin
  DNS, rejected). The simple single-app case.
- **Behind a Balancer (private).** The box is a backend; DNS points at the **Balancer**,
  and the box can be private (no public IP / firewalled to the balancer). Scaling is now
  free — **count 1…N** is just more upstreams.

"Scale a fleet 4→5" is: change the Install's count, which opens a gap; closing it
provisions a backend, deploys, and the balancer picks it up — each step an act, not a
background convergence. **The public/private choice is what unlocks scale.**

> **Exposure built 2026-08-03**, as `Install#exposure` (`edge` | `balanced`, default
> `edge`) gating `count` at validation. Restating it is `installs#update`, a recorded
> `restated intention` act that reaches no box. Splitting the gate out ahead of the
> Balancer was deliberate: without it, an install on the edge could ask for three boxes and
> get three boxes all claiming one hostname that DNS points at once. The gate is the honest
> half and it did not need the Balancer to exist — which the next section then built.
> Selecting a balancer stays *optional* even when balanced: an operator running their own
> edge only wants the count unlocked.

**Transitions.** Start an app *behind a balancer* (even at count 1) and scaling later never
touches DNS — DNS already points at the balancer; up/down is just upstreams. The only
cutover is the one-time **Edge → Balanced** move (DNS flips from the box to the balancer
once; the balancer issues the cert). Rule of thumb: anything you might ever scale starts
behind a balancer; "On the Edge" is for apps that will always be one box.

## The edge is a Balancer — a first-class managed resource

A **Balancer** is a Machine with a balancer role, running a Caddy that **Steward Console
configures**, whose **routing table is derived, not hand-authored** — reconciled from the
installs that select it. Add an install behind it → regenerate its config → reload; scale an
install → update upstreams → reload. Same plan-vs-reality loop (below), applied to the edge;
the **Balancers** page is where you see that table and the edge's health.

This is a deliberate, narrow exception to "no new noun": a Balancer earns first-class status
by its own **lifecycle, cross-project sharing, and derived control surface** — but its
*implementation* is still the Caddy-on-a-Machine primitive. It is a **role over Machine**,
not a competing primitive.

> **Built 2026-08-03, self-hosted.** `Machine#balancer` is the role — a boolean, no new
> table, because a Balancer *is* a Machine and a parallel model would duplicate address,
> key, scope and ownership and then have to be kept in step. `RoutingTable` derives the
> table from the installs that select it; applying it is the `route` act.
>
> Two things this doc's wording needed pinning down. **"Reconciled from the installs behind
> it" means derived on read, not converged in the background** — the table is computed when
> shown and again when sent, and a person presses Apply
> ([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)). And **only
> boxes actually serving are upstreams**: a placed-but-not-running or unreachable box is
> left out, because routing to it would turn a placement gap into a 502 when the whole point
> is that the gap stays visible.
>
> It also needed a Steward verb, which the box did not have — every route the app pack could
> write was `reverse_proxy 127.0.0.1:<port>`. `steward route` is that verb; see
> [`../blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md). The managed-LB
> realization is still pending.

**Ownership and sharing are the Machine model, unchanged** ([machine-ownership.md](machine-ownership.md)):

- **dedicated to one project (default)** — the project's own edge; preserves client
  isolation (capture-resistance).
- **shared to a list of projects** — the opt-in amortization: one edge box (unowned /
  operator-level) fronting several small projects. "Owned by Steward Console, usable by selected
  projects" is just *unowned + sharing=list* — no new ownership or isolation model.

**The Install's machine configuration, then:**

```
Box       → Existing box | New box (Hetzner)
Exposure  → On the Edge (public)        → count 1
          → Behind a Balancer (private) → pick a balancer → count 1…N
```

So there is still **one primitive — an Install placed on substrate** — plus a Balancer role
that is itself that primitive, made visible because it is shared and long-lived.

**The constraint that keeps it safe: replication is stateless-only.** A volume is data on
*that box's* disk; N replicas = N diverging datasets. So the count control only appears for
apps the App Library marks **replicable**; a stateful app (declares a volume) is
single-placement, full stop. That one flag removes a decision from the operator *and*
closes the footgun. (**Built 2026-08-03**, and *derived rather than stored*: an install is
replicable when it declares no volumes — `Install#replicable?`. This doc floated an
`App#replicable` flag; the flag would have been a promise *about* the spec, and it could
disagree with the spec it describes. Deriving it from the volumes the install actually
declares cannot. The gate is a validation, so a stateful install is refused a count above 1
rather than merely discouraged in the form.)

## Plan vs reality is the UI

Every entity has a **desired** state and an **observed** state; the page's job is to show
the gap and offer to close it. Both halves now exist — the observe reconciliation
([observe-reconciliation.md](observe-reconciliation.md)) supplies reality (`current_image`,
reachability, K-of-N up) against the Install's plan. `failed` / `drift` / `unreachable`
are all "reality ≠ plan," and the gap *is* the action — offered, never taken
automatically. This half of the decision was always right, and is what the auto-converge
language above contradicted.

## The one asymmetry: converging boxes is dangerous

Converging *containers* is cheap and reversible; converging *boxes* is not.

- **Provision (scale-up / new box)** — un-witnessed setup; a live status, resumable, never
  a babysitting wizard ([install-journeys.md](open/install-journeys.md) lifecycle states).
- **Deploy** — witnessed (the ceremony, record-before-act).
- **Destroy (scale-down / remove a box)** — **witnessed + friction**, and it respects the
  in-use guard ([open/status-signals.md](open/status-signals.md)). Tearing down a box that
  holds data or serves traffic is the one place "declarative all the way up" keeps a human
  firmly in the loop.

## What this settles vs. leaves open

- **Settled:** the *model* — one primitive, Install-as-intent, the machine view as the
  floor beneath it; exposure
  (Edge / Behind-a-Balancer) replaces "single vs fleet"; the **Balancer** is a first-class
  managed resource (a Machine running reconciled Caddy), **dedicated to a project by
  default**, shareable to a list; declarative-up with a witnessed scale-down edge.
- **HA for the balancer itself** is a later layer: one balancer box is a single point of
  failure, and doing it properly means two boxes plus a **floating IP** — a public IP not
  pinned to one server, reassigned to the standby on failure, so DNS keeps pointing at the
  floating IP while the IP moves between boxes. Not v1.
- **Open (build, not model):** cloud-provider provisioning; the balancer's reconciled Caddy
  + rollout orchestration; **cert handling on a shared balancer** and the **private-backend
  networking** (how a backend is reachable only by its balancer); and **HA for the balancer**
  (pair + floating IP) — all in
  [`open/console-open-questions.md`](open/console-open-questions.md). The
  **migrate-an-install** verb is now clearly "blue/green across machines" — the same
  primitive relocating one placement.
- **Build status (UI):** the install placement step currently ships an **interim
  Single / Fleet stub** (machine-first, with new-box and fleet as previews). The settled
  shape above — **Box × Exposure (Edge / Behind a Balancer) × scale**, plus a **Balancers**
  page — is the next UI rework; the stub predates this refinement.

## Roads not taken

- **Fleet as a first-class object** (a named machine set you target). Rejected: a second
  noun and a separate scaling path for what is just count + exposure on an Install.
- **Edge per fleet** (auto-create an LB when an install scales). Rejected: it couples the
  edge to one install's lifecycle, so DNS churns on every scale and the 1↔2 boundary is a
  cutover. The Balancer decouples the edge from any one install.
- **Edge per project, invisible** (a hidden shared box each project gets). Superseded by the
  **Balancer** — same DNS/scaling wins, but *visible and manageable* (its own page) and
  *optionally shared across projects*, not an invisible per-project box.
- **A load balancer as its own program/primitive.** Rejected: it's Caddy-on-a-Machine like
  everything else; a new engine would re-introduce a second model. (The Balancer is a
  *role/presentation* over that primitive, not a new one.)
- **DNS round-robin** (N A-records for one hostname). Rejected 2026-06-13: it scales, but
  fails over slowly and lossily because clients cache DNS, and per-box TLS breaks —
  HTTP-01 challenges hit a random box — without DNS-01. Graduated here from
  `open/console-open-questions.md`.
- **In-box replicas** (N containers behind one box's Caddy). Rejected the same day: real
  health-aware balancing, one IP and one cert, but bounded by a single box and no survival
  of that box dying. Not worth a Steward change for what it buys.
- **Machine-first onboarding as the spine.** Kept as an *alternate* entry (pre-provision /
  the lens), not the foundation — intent leads.
