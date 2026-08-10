# Steward Console — Overview

> The human interface to the platform. One app, whether it reaches one box or a
> hundred. Reaches Steward over scoped SSH, so it runs anywhere.

**Status:** Built and graduated — schema ([`data-model.md`](data-model.md)), the
record-as-spine interface ([`interface.md`](interface.md)), and the onboarding + install
journeys ([`journeys.md`](journeys.md)) are canonical here. The **core patterns and
boundaries** — AppConfig, MachineSpec, the Install binding, ProviderAdapter, Balancer — are
in [`patterns.md`](patterns.md) (start there for the *model*). The build roadmap for the
screens still ahead lives in
[`../../decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). Last touched
2026-06-18.

---

## What it is

Steward Console is the one human interface. It merges what used to be two ideas — a
single-machine deep-dive and fleet control — into **one app**. Same code, same auth,
whether you're looking at one box or a hundred.

The reason there is only one app: **a fleet exists nowhere but here.** Steward has no
cluster membership, no peer discovery, no awareness that another box exists — each one
is a sealed door on one machine. So a "fleet" is precisely a set of `Machine` rows and
the key each carries, and scaling from one to a hundred adds rows, not modes. There is
nothing to coordinate between stewards, which is why no program exists to do it.

Because it reaches Steward over **scoped SSH**, where Steward Console runs doesn't matter
— a container on the box, your laptop, or a central server (see the runs-anywhere note
in [`../overview.md`](../overview.md)).

Built on the [Agora Constitution](../agora.md) and **Boxcar** (a Rails pattern
language for human infrastructure, developed in tandem).

## Three rings

The console is layered the way Steward is: a **machine view** (one box, shaped by the
role it reports), **placement** across several boxes, and **tenancy** over that. Each
ring is optional above the one below, and each is authoritative about a different thing —
the machine view about nothing (it reads the box), placement about what was *asked for*,
tenancy about whose work it is.

Placement never closes the gap against reality on its own: drift is surfaced and a person
decides ([`drift-is-surfaced-never-closed.md`](../../decisions/drift-is-surfaced-never-closed.md)).
The layering, the engine split, and why an engine is not an on-box component are in
[`console-layers.md`](../../decisions/console-layers.md). Only the machine view is built.

## The spine: observe vs mutate

Everything Steward Console does is one of two things, kept apart on purpose — this is
Steward's scope ladder surfaced in the UI *and* the architecture:

- **Observe** — read the record Steward ships (status, events, the audit chain).
  Zero-privilege by construction: holds no key, opens no socket, changes nothing. A
  *fancy Sentry*. **Most of the app is this.**
- **Mutate** — issue a named, scoped, **recorded** command to Steward over SSH
  (`operate`). The dangerous, accountable side; every mutation is witnessed in
  Steward's record before it runs.

Read models built from the record on one side; command issuance on the other. Viewing
is free; acting is witnessed. The UI should make the line visible.

In code this is `Steward::Observe` vs `Steward::Mutate` (`app/services/steward.rb`):
observe reads are cached and change nothing; mutate writes an `Event` *before* it issues
the command, and is refused on a machine that holds only an observe key. The machine
page shows the two as separate panels — calm/blue for observe, bordered/amber and
labelled "witnessed" for mutate.

## The shape (data model, in brief)

Full schema → `data-model.md` (next). Mostly the old Dispatcher model, with one real
change: **`Connection` → `Machine`** — Steward Console now points *directly* at a Steward
box, not at a per-box Steward Console.

- **Machine** — a Steward box (ssh endpoint + scoped key, version, last-seen). Has an
  **owner** Project and an explicit **sharing** mode; **dedicated (owner only) by
  default**, shared across Projects only on purpose (`everyone`, or `list` + allowlist).
- **Install** — a deployed app (digest-pinned image + config), deployed to Machines
  (with replica/strategy choices held on `InstallTarget`).
- **Project** — an entity/client. `name`, contact name/email. Groups Installs and shares
  Machines. **Optional above both**: an install is placed on a box, not inside a client
  (`decisions/console-layers.md`).
- **Snapshot / Event** — the observe side: status over time, and the activity feed.

**Tenant boundary — settled:** the **Machine** is the boundary. A box is owned and serves
one Project by default (`sharing = dedicated`, DB-enforced on the join); sharing is an
explicit, visible opt-in, bounded to the projects the owner allows. The box is the trust
boundary (the `operate` key is box-wide), so isolation between Projects *is*
dedicated-by-default — see `data-model.md` Decision 1, `decisions/machine-ownership.md`,
and the isolation rule in [`journeys.md`](journeys.md).

## Journeys (in brief)

Every screen is a lens on the one record — the canonical interface (**Shape B, the record
is the spine**) is in [`interface.md`](interface.md), and the onboarding + install flow in
[`journeys.md`](journeys.md):

- **Status / Now** — the fleet pulse: exceptions and pinned entities, plus the live head
  of the record.
- **Projects → Project** — the client lens; observe-only, the shareable client status page.
- **Machines → Machine** — the box lens.
- **Installs → Install** — placement, fleet-wide: what should run where, with or without
  a client behind it. The app-actions home.
- **Record** — the full timeline, filterable by actor / action / target / time.
- **App Library** — the curated app catalog (the install front-of-funnel).
- **Settings.**

We have room to **reinvent UI patterns** here, not just inherit them.

## Open / proprietary

Steward Console is **open source (AGPL)** *and* the software the maintainer runs to manage
their own clients. Not a contradiction: the platform is open; client-specific config,
secrets, and private integrations stay out of core. See
[`../../decisions/licensing.md`](../../decisions/licensing.md).

## Open questions

Tracked in
[`../../decisions/open/console-open-questions.md`](../../decisions/open/console-open-questions.md).
