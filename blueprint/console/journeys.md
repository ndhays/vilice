# Steward Console — Journeys

> How an operator gets from nothing to a running app: register a machine, curate an app,
> install it onto a box, then drive its lifecycle through the witnessed ceremony. The
> *why* behind the bootstrap and the install shape is in
> [`decisions/machine-onboarding.md`](../../decisions/machine-onboarding.md) and
> [`decisions/open/install-journeys.md`](../../decisions/open/install-journeys.md).

**Status:** Canonical. The install page and **replicas** are built — an install is an
intention that needs no box, count and exposure are real, and a placement gap is closed one
recorded act at a time. What is still open is the async **Create Machine** path, and
whether it should ever be a branch of this form at all
([`decisions/open/create-machine.md`](../../decisions/open/create-machine.md)); the
remaining install-side threads are in
[`decisions/open/install-journeys.md`](../../decisions/open/install-journeys.md). Last
touched 2026-08-19.

---

## The spine

> **Install (pick app + version, fill what's required) → the witnessed deploy.**
> A Project may sit in front of it, and doesn't have to.

The install flow is the front half of the lifecycle; the mutate ceremony
([`interface.md`](interface.md)) is the back half, and the seam between them is built. The
flow's job is to assemble a spec with the least typing, choose a machine, and hand a
complete, witnessable deploy to the ceremony. A half-assembled install is an honest
*state*, not a lost draft (state is the head of the record).

## Onboarding a machine

A box goes from bare → reachable **without ever handing Steward Console root** — the bootstrap
is done locally and the only thing Steward Console receives is a scoped `operate` key
authorized during it. Steward Console's key is **born `operate`; it never holds root, even
transiently**. The why (and why the chicken-and-egg is a feature, not a bug) is in
[`decisions/machine-onboarding.md`](../../decisions/machine-onboarding.md).

- **Add Machine** (built) — the box is already Steward-ready. Steward Console generates an
  ed25519 keypair (`SshKeypair`; private stored encrypted, never leaves), records an
  `added machine` act, and the machine page surfaces the one line to run on the box:
  `Machine#authorize_command` → `steward authorize "<pubkey>" --client console --scope
  <scope>`. Steward Console always connects as the `steward` user (forced, not a form field).
- **Project-linked Add Machine** (built) — `machines/new?project_id=` carries a project;
  on create the machine links via `ProjectMachine` (Decision 1) and returns to the install.
- **Attach an existing machine** (built) — a project's machine pool is the staging queue
  the install flow draws from. The project page splits this into **Owned Machines** (its
  own hardware) and **Shared Machines** (boxes another project owns, shared in); the
  attach select lists only boxes that **permit** this project (`Machine#permits?`),
  Decision 1 enforced on the join.
- **Create Machine** (ahead) — cloud-init / Hetzner-API self-bootstrap, async; see the
  open doc.
- **Remove Machine** (built) — forgets the box in the control plane only; a recorded
  `removed machine` act, then back to the fleet. The box keeps running, and Steward Console's
  key stays authorized until the operator revokes it *on the box* (`Machine#revoke_command`
  → `steward revoke console`, shown in the honest confirm) — removing here never reaches
  the box. `events: :nullify` keeps the record intact; the join, targets, snapshots, and
  labels cascade, so any installs on the box are orphaned (kept, target dropped), not
  deleted. Cutting access on the box is the Access (#16) grant-scope work, still ahead.

## The App Library — the front-of-funnel

A curated directory of apps the admin can install onto machines: saved definitions (name,
default port/health, declared env, versions) that make the *first* install easy and
consistent. It is **bookmarking / curation, not a security boundary** — the un-bypassable
image allowlist is a separate Steward-side concern (see
[`decisions/open/app-library.md`](../../decisions/open/app-library.md)). The catalog model
(`App → Version`, the three-tier `App → Install → InstallTarget`, the manifest import/
export) is specified in [`data-model.md`](data-model.md).

- The library is a **pure directory** — it has no install action.
- A release carries a **tag and a digest**. **Look up digest** asks the registry what a
  tag points at and fills the field in; it saves nothing, and nothing re-resolves later
  ([`a-tag-is-not-a-release.md`](../../decisions/a-tag-is-not-a-release.md)). Public
  registries only — a private one's credential lives on the box, by design.
- Curating it (add / edit / version / remove) is a recorded **own-record** act.
- A singleton `Setting.installs_library_only` (default on) gates the install image source:
  on → pick a library app; off → a library app **or** a custom typed image. A **guardrail,
  not security** — bypassable by a direct scoped-SSH deploy.

## The install flow

Installs live at `/installs` — placement is its own layer, not something a client
contains ([`decisions/console-layers.md`](../../decisions/console-layers.md)). **A project
is optional context and arrives in the URL** (`installs/new?project_id=`, the same shape
`machines/new` already uses), never as a dropdown: with one, the machine list narrows to
that project's boxes and the trail runs through the client; with none, this is plain
fleet-wide placement and nothing asks you to invent a client first. The flow leads with
**scale** — the Install is intent, and how much of it comes before where it lands
([`one-primitive-composed.md`](../../decisions/one-primitive-composed.md)).

1. **Scale** — one box or several, and how it is reached.
   - **Single machine** vs **Fleet** — not a mode, a **count** (1 vs N). There is no Fleet
     object, and scaling later is just the number. The count is **real**: it is the
     intention, and stating 3 opens a gap the moment fewer than 3 boxes are serving. You
     close it one recorded act at a time (**Place on another box**), never automatically.
   - **Exposure** decides whether that number may exceed 1. *On the edge*, DNS points at
     the box and the count is pinned to 1; *behind a balancer*, the box is a backend and
     the count is free. Both gates are validations, not hints — and the second gate is
     statefulness: an install declaring a volume is single-placement either way.
     *(Still previewed: a balancer the console actually manages. Marking an app balanced
     states the topology; pointing something at those boxes is yours.)*
   - Both are editable afterwards — **Change what's asked for** on the install, recorded as
     a `restated intention` act. Asking for fewer boxes never removes anything.
2. **First box — optional, in both branches.** An install is an intention, and **an
   intention does not need a box**. Requiring one made the claim depend on the very
   reality it exists to be compared against, which is the merge
   [`drift-is-surfaced-never-closed.md`](../../decisions/drift-is-surfaced-never-closed.md)
   refuses. Leave it blank and the form writes the intention and lands on the install's
   own page, showing the gap it just opened — `unplaced`, *asked for 3 · serving 0* — a
   state the model, the list, the badges and the copy already knew how to render and only
   this form refused to create. That is also what makes **Fleet** submittable: there is no
   "first box" problem once no box is required.
   - The choice is **an existing box** — the project's, or any operate-scoped box in the
     fleet when there is no project. **Provisioning one from here is not offered**;
     whether the console should ever birth a box mid-install is still open
     ([`create-machine.md`](../../decisions/open/create-machine.md)).
   - Blank and refused are different answers. A box this install *may not* land on is an
     error, not a quiet downgrade to unplaced — dropping a named choice in silence is its
     own failure.
   - A box we have never reached carries **"not yet authorized"** on the option itself.
     The authorize gap is stated before the choice rather than discovered when the SSH
     call fails ([`what-could-go-wrong.md`](../../decisions/open/what-could-go-wrong.md)).
3. **Choose an app** from the catalog (a real picker, searchable, shows version + labels —
   not a `<select>`). Selecting it resolves the **version** inline (default **latest**, an
   inline override pins an exact one) and configures everything below: name, port, health,
   the env schema. **The spec is still required** — "deploy something, we'll decide what
   later" is not an intention, it is a blank.
4. **Hostname** — the always-custom required field.
5. **Confirm** — name (the app name), Port/Health labelled **"App Default"** (app-owned,
   rarely touched; override under Advanced), optional env.
6. **Deploy** — the existing witnessed ceremony, and only when a box was named.

**Two decisions, two records.** One transaction writes the `Install` and an `added install`
act, which names no machine and reaches nothing; if a box was chosen it *also* writes the
`InstallTarget` and a `placed install` act — the same verb the standalone **Place on a box**
door records, through the same `Install#place_on!`. One act standing for two decisions was
the anomaly, and it meant the two doors into a placement disagreed about what to call it.

**One name for one thing.** The list's button, the crumb, the heading and the submit all
read **Add Install**, and the act is `added install` — they were four different names for
one journey (*Add Install* / *Create New Install* / *Create New Install for Acme* /
*Create Install and Deploy*). The project rides the crumb, not the heading, the same way
Add Machine leaves its owner to the Owner step.

The submit wears `plus`, the glyph of the act it performs. It used to promise "and
Deploy", which was true only when a box happened to be picked and blurred the line that
matters: **setup is control-plane, the deploy is a witnessed ceremony of its own.** With a
box, that ceremony is the next screen and still asks. With none, the install page is —
carrying the gap, and the act that closes it.

The steps read **Scale · First box · App · Hostname · App defaults · Storage**, following
the reference shape in [`interface.md`](interface.md). Two legends were replaced rather
than restyled: *Machine Configuration* was jargon for a plain idea and had stopped being
true once the box moved to its own step, and *Details* named nothing at all — those three
fields are the app's own facts, arriving prefilled and overridable for this one install.

**Scaling is the same journey, one box at a time.** An install asking for more boxes than
are serving shows the gap on its own page and on Status; **Place on another box** picks a
candidate, records a `placed install` act, and hands off to the same deploy ceremony. The
gap does not narrow when the placement is made — only when the box reports the app running,
because the right-hand side of the comparison is always the box. Scaling down is the
existing `remove` verb, which retires the target.

> Most fields are **prefilled — confirm/override, not entry.** The progressive-reveal
> single-page form (reveal each section as the prior choice is made, with a Preflight panel
> and a required-env step) is **being built** — see the open doc.

## The lifecycle (back half — built)

Once installed, every act runs through the mutate ceremony, targeting an `Install`'s live
target(s): **deploy / rollback / start / stop / restart / remove**, plus machine-level
**apply-updates**. Remove retires the `InstallTarget` (the row is kept for history). The
Install has a show page that hosts these witnessed verbs per target; the Machine page keeps
the same verbs as the sysadmin lens (one shared partial, one return-aware ceremony). A
successful deploy pins `InstallTarget.desired_image`; `current_image` is reconciled from
what the box reports, so drift is honest. (`reboot` is deliberately **not** a verb — the
settled Steward command set has no machine reboot.)

## Isolation — the rule the flow rests on

The guarantee: *unless a box is explicitly shared, no Project can be cross-contaminated by
another.*

**The box is the trust boundary — by design.** The `operate` key is box-wide: it can
`deploy`/`remove`/`status` any app on that box; Steward has no notion of "tenant"
(a small, legible ceiling). So isolation between projects is **not** a wall inside a shared
box — it is **not sharing the box**. That is why **dedicated is the default**
(`Machine.sharing = dedicated`, owner only), DB-enforced on the join rather than left to
convention (see [`data-model.md`](data-model.md) Decision 1). Sharing a box (`everyone`,
or `list` + an allowlist) is an explicit, visible, witnessed opt-in — and bounded to the
projects the owner allows, so it never reaches another client by accident.

On a shared box the care is Steward Console-side discipline — **no Steward change for v1**:

1. **The project lens never leaks** (the most important rule). `steward status` / `record`
   return *everything* on the box, but the Project page — the shareable client status page
   — renders **only that project's own Installs**, never raw box status. A client viewing
   Project A must never see Project B.
2. **Uniqueness guards** at install time (built): install **name** and **hostname** are
   unique **per machine** (`InstallTarget` validation), so two projects can't collide on
   the box's `apps/<name>.json` or hijack each other's route. This is the *only* uniqueness
   rule installs have — it holds across the project boundary and for placements with no
   project at all, which is what lets tenancy be optional. Volumes are now declared on the
   `Install` (`config.volumes`); a **volume-name** uniqueness guard on a shared box is the
   remaining gap — two projects could still name the same named volume.
3. **Noisy neighbor** is inherent to sharing; `OOMScoreAdjust`/`MemoryMax` mitigate, and
   choosing Shared means accepting the risk, said plainly at the moment a box is marked
   shared.
4. **Decommission asymmetry**: removing a *dedicated* box can tear it down; removing an
   install on a *shared* box leaves the other tenants running.

The only thing that would ever need Steward is *un-bypassable* per-app isolation **inside**
a shared box (a scoped-per-app key) — the "separate, simple, maybe later" item in
[`decisions/open/steward-open-questions.md`](../../decisions/open/steward-open-questions.md),
rarely necessary because dedicated is the default.

## Common pitfalls

The failures an operator hits onboarding and installing — the cloud-provider firewall (the
biggest gotcha), DNS/ACME timing, the authorize gap, provisioning failure — are collected,
fix-first, in
[`decisions/open/what-could-go-wrong.md`](../../decisions/open/what-could-go-wrong.md).
