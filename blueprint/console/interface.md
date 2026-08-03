# Steward Console — Interface

> How Steward Console looks and behaves: the record is the spine, observe and mutate are
> kept apart, and every screen is a lens on the one record. The *why* — and the shapes
> rejected — is in [`decisions/ui-shape.md`](../../decisions/ui-shape.md).

**Status:** Canonical (the shape is settled and largely built — Waves 1–3). The build
roadmap and the screens still ahead live in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). Last touched 2026-08-03.

---

## The shape: the record is the spine

The protagonist of the UI is the **record** — what happened, who did it, what it touched
— not the current state. Current state is just *the head of the record*. This is the one
thing no server-admin panel copies, because they don't keep the chain. Everything below
follows from that choice.

### The design law: a view shows what it's FOR

Every screen surfaces **what it's for** — the answer, the most relevant state — not the
inputs you typed to make it. One level down from "the record is the protagonist." It is
what justifies showing a machine row's address as plain truth (the SSH user is always
`steward`, so `steward@host:22` is noise — drop it) and showing the box's reported name
plainly rather than guarding it with a match/mismatch check (the SSH connection is already
verified; a wrong box surfaces on its own).

## The spine in two halves: observe vs mutate

Everything Steward Console does is one of two things, kept apart on purpose — Steward's scope
ladder surfaced in both the UI and the architecture (see
[`overview.md`](overview.md) and `app/services/steward.rb`):

- **Observe** — read the record Steward ships. Zero-privilege: holds no key on the read
  path, changes nothing. Calm, blue. **Most of the app is this.**
- **Mutate** — issue a named, scoped, **recorded** command over SSH. Bordered, amber,
  labelled "witnessed." Every mutation writes its `Event` before it runs.

**Viewing is free; acting is witnessed** — and the line is made physical in the layout.

## The record is two streams

The UI keeps them apart:

- **The audit chain** — discrete *acts* (deploy, grant, restart). Append-only,
  hash-chained, actor-tagged. **This is the spine** (`Event`).
- **The status series** — continuous *health* (load/mem/disk over time). Feeds the
  health narratives and sparklines (`Snapshot`).

Rule that keeps the timeline legible: **show acts always; show status only at
transitions** ("went critical 03:12", "recovered 03:40").

## Navigation — every screen is a lens on the one record

```
Status · Projects · Machines · Installs · Record · Access · App Library · Settings
```

**Installs sits between Machines and the rest on purpose.** The three rings of
[`decisions/console-layers.md`](../../decisions/console-layers.md) — machine view,
placement, tenancy — each optional above the one below, and the nav puts the box first
and placement next to it.

- **Status** (the "Now" page in this doc's older wording) — the fleet pulse. Calm by default ("12 installs, all healthy · last act 4m
  ago"); exceptions rise to the top, the healthy fold to a count. The unit of concern is
  the **install** — installs in a bad-but-actionable state (failed / machine-unreachable /
  drift) lead the page, rendered through the same row as the project and fleet lists.
  Unreachable **machines** follow as the root cause: one down box explains many down
  installs, and it's fixed there. Carries the live head of the chain.
- **Record** — the full timeline, filterable by actor / action / target / time. The
  forensics surface; the thing nobody else ships.
- **Projects → Project** — the client lens; observe-only, the shareable client status
  page. A lens over placement, not a container for it: its Installs list is *this
  client's* placements, and the project column is dropped there because it would only
  repeat the page.
- **Installs → Install** — placement, fleet-wide: what should run where. One ring above
  the machine view (which reads a single box) and below Projects. The list carries every
  placement, with the project shown where there is one and a plain dash where there isn't
  — an install with no client is a legitimate state, not missing data. The Install page
  is the app-actions home
  ([`decisions/install-the-app-actions-home.md`](../../decisions/install-the-app-actions-home.md)).
- **Machines → Machine** — the box lens, and it is **pack-shaped**: sections exist
  because the box reports the pack (`steward packs`), not because the console assumed
  it. A box running only the core shows no Apps section — not greyed out, absent,
  because that box genuinely cannot deploy. A pack that is authorized but cannot run
  (stale digest, missing, unauthorized) surfaces *why*, since "stale" alone is
  indistinguishable from tampering until you can see that an upgrade skipped
  `prepare`. An unreachable box reports what runs there as **unknown, not none**.

  **A machine-view deploy is stateless in the console.** Paste an AppConfig, it goes to
  the box on stdin, and it is *discarded* — no `Install`, no `Project`, no stored spec.
  What is running afterwards is read back from the box, whose record is the only
  record. That is deliberate: a stored copy of the spec would be a second, quieter
  answer to "what is supposed to run here," which is the intention layer's job one ring
  out, where the gap against reality is visible rather than assumed away.

  The console validates only that the config is a JSON object and that its name
  matches the name being deployed under. Everything else is the box's to judge — it
  validates at the render boundary and refuses what it cannot render, and a second copy
  of those rules here would drift from the first.
- **Access** — the rights ledger: who can touch what, at which rung
  (`observe ⊂ operate ⊂ grant`). Read straight off each box through `steward actors`,
  never from a stored copy — `authorized_keys` *is* the ledger, and a mirror of it here
  would be a second answer to "who can act on this box" that could quietly disagree
  with the box. So the page has no model behind it and nothing to keep in sync.

  It leads with the keys **Steward did not write**. A line with no forced command is a
  way onto the box that skips the gate entirely, and this is the only screen that can
  ever show it. An unreachable box reads as *unknown*, not as *nobody* — the dangerous
  misreading is an empty list meaning "no one has access."

  Observe only. Granting and revoking are acts, and they happen where acts happen.
- **App Library** — the curated app catalog (the install front-of-funnel — see
  [`journeys.md`](journeys.md)).
- **Settings.**

## The one page pattern

Every entity — Machine, Install, Project — renders the same shape:

1. **Header** — name · health dot · plain-language narrative · scope/rights badge.
2. **Head** — current state as the latest projection (live status for a Machine; running
   digest + health for an Install).
3. **Chain** — the record filtered to this entity, **as the body of the page, not a
   footer**. Acts plus status transitions, newest first.
4. **Mutate zone** — witnessed actions, visually set apart (the amber "this will be
   recorded" zone).

The inversion: the timeline is not a tab or a bottom-of-page feed. It **is** the page,
and current state is its most recent vertebra.

## The hero interaction — the mutate ceremony

One component for *any* witnessed act (deploy, rollback, start/stop/restart, remove,
apply-updates):

1. **Compose** — pick what (image digest, target). Only acts that need it (deploy).
2. **Preview the record entry** — show the exact accountable line before it runs:
   `nick · deploy · acme-web · @sha256:abc → db-1`, rendered with the real chain styling,
   nothing written. The record-before-act invariant *is* the confirm dialog.
3. **Confirm** — the friction. Friction is a feature on the dangerous side.
4. **Settle** — the outcome is stamped on the same entry (`pending → ok/failed`). Rollback
   is a *new witnessed act*, never a silent undo.

Verbs come from an allowlist (`Mutation::ACTS`), never raw input. The deploy/rollback path
pipes the desired-state envelope on scoped-SSH **stdin** so secret values never ride the
recorded command line. The settle step reuses the **same timeline component** the observe
side renders — the deploy screen isn't special, it's the record, live. That is how the
record-as-spine model avoids becoming two apps.

> **Live "watch" is still ahead** (a deploy currently blocks until it settles). Streaming
> an act's sub-steps in place — pull → start color → health → flip → drain — needs a
> Steward sub-step protocol; tracked in the open roadmap.

## Principles to hold

- **Viewing is free; acting is witnessed** — every mutate confirm shows the record entry
  it will write.
- **State is the head of the record** — stop splitting "what is" from "what happened."
- **Calm by default; lead with exceptions** — no wall of green.
- **Plain-language health narratives** — on-brand with the Orwellian naming rule.
- **The rights ledger is visible** — authorize/revoke as a surface, not buried config.
- **Friction on mutate; frictionless on observe.**
- **No mode-switching** — one app, one lens that widens (Dispatcher dropped as a concept;
  see [`decisions/ui-shape.md`](../../decisions/ui-shape.md)).

## Theme

CSS custom-property tokens (color, spacing, type) with a persisted light/dark toggle and
swappable skins; a cohesive WCAG-AA palette; the ported lucide icon set; **mono = machine
truth** (raw box values render monospaced). The universal **label** system (segmented
key/value tags, polymorphic on Project/Machine/App) is the operator's own grouping axis,
distinct from the system's status/scope badges — see
[`data-model.md`](data-model.md).

## Build state

The shape above is settled. What is realized vs. still ahead — ingestion (#6), the
generic focus/pin lens (#10), the secret/env panel (#14), live-watch (#15), Access (#16),
the chain-integrity badge (#17), the shareable client view (#18), the command palette
(#19), and Steward Console-deploys-Steward Console (#20) — is tracked wave by wave in
[`decisions/open/ui-roadmap.md`](../../decisions/open/ui-roadmap.md). When a screen lands and
settles, its canonical description moves here.
