# Steward Console — App Journeys (open build)

> The app spine (**App → witnessed deploy**, with a Project as optional context),
> the built front-of-funnel, the machine step, and the **isolation rule** are graduated to
> [`blueprint/console/journeys.md`](../../blueprint/console/journeys.md). What remains
> here is the part still being built: the progressive-reveal page, the async app
> lifecycle, and replicas.

**Last touched:** 2026-08-03.

---

## Open: does a placement outlive its client?

Raised by the `App → Project` inversion
([`../console-layers.md`](../console-layers.md)). `Project has_many :apps, dependent:
:destroy` predates the inversion, when an app *couldn't* exist without one. Now it can,
so deleting a client could equally **nullify** — leaving an untenanted placement — instead
of destroying it.

Neither reading is dangerous today: deletion is already refused while any target is live
([`../drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md)'s corollary
in practice — forgetting a client must not remove apps from boxes), so only retired
apps are ever at stake. Destroy loses their rows; nullify leaves dead placements in the
fleet-wide list forever. The question is which is less misleading, and it wants the
`steward-projects` engine to answer it — that is when "delete the tenant" gets a real
meaning.

---

## The progressive-reveal app page — being built

Not a modal, not a multi-URL wizard (both reintroduce the "pop back into your flow"
problem). **One app page that reveals each section as the prior choice is made** (Turbo
frames, server-rendered, degrades to all-visible with no JS). The reveal *is* the measured
flow: a non-tech user meets one decision at a time; a pro sees defaults fill in and edits
any field.

**Started:** step 1 (catalog app picker + inline version, default latest) and the step
skeleton (hostname → machine → details, revealed once an app is chosen; the `install-form`
Stimulus controller). **Ahead:** the Preflight panel, the required-env step, and the
machine dedicated/shared framing.

### Preflight — check early, warn don't gate

Once hostname + machine are known, run one **Preflight panel** over the real gotchas
([`what-could-go-wrong.md`](what-could-go-wrong.md)):

- **Reachability** — can Steward Console SSH the box? (the biggest gotcha is the cloud-provider
  firewall, not DNS).
- **DNS** — does the hostname's A record point at this box's IP? If not, show the exact
  record to create.
- **Ports** — are 80/443 reachable?

Two rules: it's a **warning with guidance, not a hard block** (DNS not set yet → offer
*"deploy anyway / set DNS later"*; Caddy gets the cert once it propagates). And **timing is
path-dependent**: an existing box has an IP → check now; a new dedicated box has no IP yet →
the check moves to the `awaiting_machine → ready` transition.

## Resolved 2026-08-18: an app does not need a box

The create form now accepts a blank box, and that answers more than it looks like.
`App#count` was always the intention and `unplaced` was always a state the model,
the list, the badges and the gap copy could render — only the form refused to make one.
Requiring a box made the claim depend on the reality it exists to be compared against.

Two things below were sized against that constraint and shrink with it:

- **Replicas' "provisioning the backends"** is not a create-form problem. A fleet app
  is stated once and closed one `placed app` act at a time, exactly like scaling an
  existing one — it was only blocked because the form demanded a first box.
- **The lifecycle states below** were bought almost entirely to carry an app across a
  wait. An app that never needed a box has nothing to wait *for*: a box that does not
  exist yet is a gap, and a gap is already a first-class, resumable, honest state. See
  the open question at the head of [`create-machine.md`](create-machine.md) — if
  provisioning is its own act rather than a branch of this form, the ladder below may
  never need to be built at all.

## The app carries itself — lifecycle states (for the async path)

> **Under review** — see above. Written when an app could not exist without a box.

For the automated **Create Machine** path ([`machine-onboarding.md`](create-machine.md))
the app must advance across an async provision without a babysitting wizard, so
`App`/`Placement` need honest, resumable states:

```
composing → awaiting_machine → ready → deploying → running
                  ↓                ↓         ↓
               failed           failed    failed   → retired
```

- **composing** — being filled out (may not persist until submit).
- **awaiting_machine** — a dedicated box is provisioning; the page is a live status.
  Provisioning is **un-witnessed setup**.
- **ready** — the box is live and has authorized Steward Console's operate key; the app sits
  at the **witnessed deploy confirm**. Setup was automatic; the deploy stays a ceremony.
- **deploying → running** — the existing ceremony (pending `Event` → settle).
- **failed / retired** — provisioning failed, deploy failed, or removed.

The existing **existing-box + manual** flow doesn't require these async states yet; they
land with Create Machine.

## The env schema (the smooth path)

The App declares its environment as a small schema so the app form is mostly prefilled —
`required + public` blocks on a blank field; `optional` is prefilled + under Advanced;
`secret` is masked, off-record (the #14 channel). The declaration half is built (names only);
the value half and the `required?`/`default` fields are the open #14-B work in
[`app-library.md`](app-library.md).

## Replicas / scale — the build, not the model

The model is settled ([`../one-primitive-composed.md`](../one-primitive-composed.md),
canonical in [`patterns.md`](../../blueprint/console/patterns.md)).

**The count half is now built.** `App#count` is the intention, the gap against what the
boxes report is surfaced and never auto-closed
([`../drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md)), and
**Place on another box** is the act that closes it — so an app can genuinely span N
boxes today, one recorded placement at a time. The stateless-only gate is enforced.

**Exposure is built too**, and it is what keeps the count honest: on the edge DNS points at
one box, so `count` is pinned to 1 there and only a balanced app may ask for more. The
app UI is now **Box × Exposure × scale**, and both halves of the intention are editable
after the fact.

**The self-hosted Balancer is built too.** A box takes the role, apps select it, its
table is derived from those apps, and `steward route` applies it as a witnessed act.
Selecting one stays optional — an operator with their own edge (Cloudflare, a cloud LB)
just wants the count unlocked, and that is still a supported configuration.

**And a fleet app can now be created as one.** The create form no longer demands a
first box, so stating *three, behind this balancer* is a single submit that opens a gap of
three; the stub that used to sit on that branch is gone.

What remains: **rollout orchestration** across a balanced app's targets (today a deploy
is per-box and N boxes is N acts, with no drain-then-flip across the set), the
**managed-LB** realization, and the private-backend jump.

Open, and newly answerable: **should a placement gap page someone?** The decision says
nobody gets woken by a self-healing system because there isn't one — they get woken by "three
asked for, two serving." The console now knows that number. Whether it should notify, and
through what, is untouched.

Sharper than it was, because the console now also knows whether the gap is *closable*
(`App#ready_to_place?`). Those are not the same page: "three asked for, two serving,
and a box is sitting there" is a click someone forgot, while "and nothing is free to take
it" is an errand. If gaps ever notify, they are two different messages, and probably only
the second is worth waking anyone for.

**Also open: readiness fleet-wide, as a group rather than a call-out.** Status names the
stuck apps and each app page answers for itself, but the Apps list cannot yet
be *grouped* by whether a gap is closable. `AppGroups`' axes are `->(app)` lambdas
with nowhere to hand a preloaded pool, so an axis that asked this question would reintroduce
the per-row query the pool exists to avoid. It wants either a preload seam in `Groupings` or
a stored column — and a stored one would have to be a mirror of a reading, never a claim,
which is the part to think about before building it.
