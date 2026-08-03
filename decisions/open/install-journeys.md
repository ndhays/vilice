# Steward Console — Install Journeys (open build)

> The install spine (**Install → witnessed deploy**, with a Project as optional context),
> the built front-of-funnel, the machine step, and the **isolation rule** are graduated to
> [`blueprint/console/journeys.md`](../../blueprint/console/journeys.md). What remains
> here is the part still being built: the progressive-reveal page, the async install
> lifecycle, and replicas.

**Last touched:** 2026-08-03.

---

## Open: does a placement outlive its client?

Raised by the `Install → Project` inversion
([`../console-layers.md`](../console-layers.md)). `Project has_many :installs, dependent:
:destroy` predates the inversion, when an install *couldn't* exist without one. Now it can,
so deleting a client could equally **nullify** — leaving an untenanted placement — instead
of destroying it.

Neither reading is dangerous today: deletion is already refused while any target is live
([`../drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md)'s corollary
in practice — forgetting a client must not remove apps from boxes), so only retired
installs are ever at stake. Destroy loses their rows; nullify leaves dead placements in the
fleet-wide list forever. The question is which is less misleading, and it wants the
`steward-projects` engine to answer it — that is when "delete the tenant" gets a real
meaning.

---

## The progressive-reveal install page — being built

Not a modal, not a multi-URL wizard (both reintroduce the "pop back into your flow"
problem). **One install page that reveals each section as the prior choice is made** (Turbo
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

## The install carries itself — lifecycle states (for the async path)

For the automated **Create Machine** path ([`machine-onboarding.md`](create-machine.md))
the install must advance across an async provision without a babysitting wizard, so
`Install`/`InstallTarget` need honest, resumable states:

```
composing → awaiting_machine → ready → deploying → running
                  ↓                ↓         ↓
               failed           failed    failed   → retired
```

- **composing** — being filled out (may not persist until submit).
- **awaiting_machine** — a dedicated box is provisioning; the page is a live status.
  Provisioning is **un-witnessed setup**.
- **ready** — the box is live and has authorized Steward Console's operate key; the install sits
  at the **witnessed deploy confirm**. Setup was automatic; the deploy stays a ceremony.
- **deploying → running** — the existing ceremony (pending `Event` → settle).
- **failed / retired** — provisioning failed, deploy failed, or removed.

The existing **existing-box + manual** flow doesn't require these async states yet; they
land with Create Machine.

## The env schema (the smooth path)

The App declares its environment as a small schema so the install form is mostly prefilled —
`required + public` blocks on a blank field; `optional` is prefilled + under Advanced;
`secret` is masked, off-record (the #14 channel). The declaration half is built (names only);
the value half and the `required?`/`default` fields are the open #14-B work in
[`app-library.md`](app-library.md).

## Replicas / scale — the build, not the model

The model is settled ([`../one-primitive-composed.md`](../one-primitive-composed.md),
canonical in [`patterns.md`](../../blueprint/console/patterns.md)) and the data model is
ready. What remains is build: the balancer's reconciled Caddy + rollout orchestration,
provisioning the backends, and the private-backend jump. The install UI still ships an
**interim Single/Fleet stub** and reworks to **Box × Exposure × scale**.
