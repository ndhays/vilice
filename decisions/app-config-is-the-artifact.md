# The AppConfig is the artifact — first-class, self-versioned, content-addressed

**Decided 2026-06-24**; absorbed the companion philosophy note *"A deploy is an artifact,
not a process"* (2026-06-30) on 2026-08-03 — it existed only to name the reasoning under
this decision, and two documents for one idea is one too many. Promotes the AppConfig from
a mutable field to a first-class, self-versioned artifact with its own identity. Settles the slot fork left open in
[`open/deploy-config-model.md`](open/deploy-config-model.md) ("files on the box vs.
entries in the record — the first thing to decide") and the "where the truth lives"
question there. Builds on the *config-is-the-app* frame in that doc and on
[`one-primitive-composed.md`](one-primitive-composed.md).

## Why an artifact and not a process

A deploy tool can own one of two things: the **process** or the **artifact**.

Own the process, and the deploy *is* the tool's in-flight state — a pipeline of diffs,
merges, and validations that only exists while it runs. Nothing settles into a thing you
can hold. You can't diff it, re-run it cleanly, reason about it offline, or say "give me
exactly what is deployed." When it breaks, you are stuck inside the procedure with it.

We own the **artifact**. The AppConfig is a content-addressed document that exists
independent of whatever produced it. A deploy is one sentence — *seat a known digest in a
slot* — and rollback, restore, and "adopt what the box runs" are all the same cheap move:
re-seat a digest. The procedure is reduced to a noun.

### What follows from that

- **The editor is a producer, not the system.** Steward Console mints the artifact; the
  [Steward CLI](../blueprint/vilice/overview.md) mints the same artifact from hand-written
  JSON. Delete either and the system stands, because the unit that moves is the document,
  not the tool. A tool that hoards state nothing else can reconstruct has failed this test;
  ours checkpoints its state into a portable artifact on every change.
- **The artifact is intent, not truth.** The AppConfig is authoritative for *desire* — what
  you want — not for reality. The box owns reality; on conflict, the observed digest wins,
  and adopting it back into intent is an explicit, witnessed act
  ([`observe-reconciliation.md`](observe-reconciliation.md)). "Golden" and "source of truth"
  are different axes: the document is the canonical statement of intent, and it never claims
  to describe the box.
- **The editor's real product is the timeline of intent.** The JSON is the checkpoint form;
  what the editor owns that a single mint does not is the accountable, hash-chained record of
  *who changed intent, when, and why* — the Agora invariants applied to desire itself.

## The decision

The AppConfig is the unit the whole system turns on. It gets **golden-statue status**:
it is a **first-class artifact with its own identity, addressed by its own digest, and
versioned on its own accord** — not a throwaway blob that happens to hang off an
`Install` row. It can still change; a change just **mints a new version**, it does not
mutate the old one.

The same inviolable rule the binary already lives under
([`versioning.md`](versioning.md): *a version is one set of bytes, forever*) now applies
to the config: **one AppConfig digest is one set of values, forever.** Edit it and you
get a *new* digest, never re-pointed bytes under the old one. That is what makes
rollback, restore, drift, and "adopt what the box is running" all the same cheap move —
re-seat a known digest.

Conceptually it is a file type — *the `.app`*: the operator's exaggeration, made
literal. We keep the established name **AppConfig** in code and prose; `.app` is the
natural name for the digest-addressed interchange form if/when one is needed (it would
be the deploy-spec sibling of the App Library's YAML manifest).

## The slot holds a timeline, not a config

A **slot** is the app's stable identity (its name); the AppConfig is what fills the slot
right now. Promoting the config means the slot stops *being* a config and starts
*pointing at a timeline of them*, one marked current:

- **On the box:** keep each applied config, not just `prev_image`. Layout:
  `apps/<name>/current.json` + `apps/<name>/history/<digest>.json` (the box stays able to
  stand alone — the timeline is reconstructable from the record + what's on disk). This
  replaces today's single `apps/<name>.json` + `prev_image`.
- **In Steward Console:** the `Install` row is the slot; it points at a series of AppConfig
  versions (one current), rather than holding the live config in its `config` jsonb
  column. The jsonb-on-`Install` shape is the *road not taken* (below).

A deploy is then one sentence unchanged: *seat an AppConfig (which names its code, data,
and secrets) in a slot at time T, and record it.* Rollback / restore-config = re-seat a
prior digest. Blue/green `-a`/`-b` colors are **not** slots — transient implementations
of one slot mid-cutover, as before.

## Two timelines, kept distinct — don't blur with App Library `Version`

There are now two version histories, and they must not be conflated (Orwell test — same
word for two things is the failure):

| Timeline | What it versions | Whose | Lives |
|---|---|---|---|
| App Library **`Version`** | the **code** (an image digest) a catalog app releases | the publisher's | the App Library / manifest |
| AppConfig **artifact** | the **whole deploy spec** (image is one field of it) | the operator's, per slot | the slot's timeline (box + `Install`) |

The image digest is just *one field inside* an AppConfig. A library `Version` bump is one
reason an operator mints a new AppConfig; a config-only edit (a hostname, an env value) is
another. Keeping them separate is what lets "update the code" and "change the config" stay
distinct, separately-witnessed acts — the split [`open/deploy-config-model.md`](open/deploy-config-model.md)
already insists on, now carried by *which field of the document* changed, under one
addressable identity.

## Where the truth lives — the artifact is the unit that moves

The two-records model ([`two-records.md`](two-records.md)) already answers
authoritative-on-conflict once the config is an addressable artifact:

- **Steward Console owns desire.** The DB is where a human *edits* the spec; editing mints a
  new AppConfig version. This is the source you change.
- **The box owns reality.** Steward converges one box to one AppConfig and keeps its own
  copy + record; an observe read mirrors *which digest is running*
  ([`observe-reconciliation.md`](observe-reconciliation.md)).
- **Drift is digest ≠ digest.** When the box runs a digest the slot's current doesn't
  match (a breakglass SSH edit, a half-applied deploy), that *is* the drift signal — no
  string-diffing, just two identities.
- **"Adopt" is an explicit, witnessed act.** Pull-imports-*reality*: importing the box's
  running config as a new desired version is an operator move, never a silent overwrite.
  So push and pull both exist without two writers fighting over one document.

## Roads not taken

- **Config as a mutable jsonb blob on `Install` (today's shape).** It makes "the current
  config" cheap but has no identity, no timeline, and no honest drift signal — rollback
  has to reconstruct, restore is special-cased, and a box edit is invisible. Promoting the
  artifact pays a small modeling cost (a version table / box history dir) and collapses
  four features into one re-seat.
- **Reusing App Library `Version` for config versions.** Rejected — see the two-timelines
  table. One is the publisher's code release; the other is the operator's deployed spec.
  Same word, two things.
- **A digest endpoint / floating "latest config."** Same reason the binary takes an
  explicit version ([`versioning.md`](versioning.md)): a deploy should name exactly the
  config it seats, not chase a moving target. "Current" is a pointer the slot holds, not a
  name a deploy resolves at apply time.

## Consequences (design pending, principle settled)

- The box layout moves from `apps/<name>.json` + `prev_image` to a per-slot timeline
  (`current.json` + `history/`); folds into [`../blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md).
- `Install` gains a config-version timeline rather than a live `config` jsonb; folds into
  [`../blueprint/console/data-model.md`](../blueprint/console/data-model.md) when
  built. Until then those docs describe today's shape — this decision is the direction,
  not yet the schema.
- Accessories (now in scope — see [`open/vilice-open-questions.md`](open/vilice-open-questions.md))
  become **fields inside the AppConfig artifact**, so they version with it: change the
  Redis you depend on and you mint a new config, same as any other field.
