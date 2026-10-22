# The AppConfig is the artifact — first-class, self-versioned, content-addressed

> Decided 2026-06-24. Settles the slot fork and "where the truth lives" in
> [`open/deploy-config-model.md`](open/deploy-config-model.md). Builds on
> [`one-primitive-composed.md`](one-primitive-composed.md). **Principle settled, schema
> pending** — the blueprint still describes today's shape (see Consequences).

## The decision

The AppConfig is a first-class artifact with its own identity, addressed by its own
digest. **One AppConfig digest is one set of values, forever** — the rule the binary
already lives under ([`versioning.md`](versioning.md)). An edit mints a new digest; it
never changes the bytes under an old one.

A deploy is then one sentence: *seat a known digest in a slot, and record it.* Rollback,
restore, and "adopt what the box runs" are the same move — re-seat a digest.

The name in code and prose stays **AppConfig**. `.app` is the natural name for a
digest-addressed interchange file if one is ever needed.

## Why an artifact and not a process

A deploy tool that owns the *process* holds the deploy as in-flight state: you cannot diff
it, re-run it cleanly, or ask for exactly what is deployed. Owning the *artifact* means
the document exists apart from whatever produced it.

- **The editor is a producer, not the system.** The console mints the artifact; the CLI
  mints the same one from hand-written JSON. Delete either and the system stands.
- **The artifact is intent, not truth.** It is authoritative for what you want. The box
  owns reality; on conflict the observed digest wins, and adopting it back into intent is
  an explicit, witnessed act ([`observe-reconciliation.md`](observe-reconciliation.md)).
- **What the editor adds is the timeline of intent** — who changed it, when, and why.

## The slot holds a timeline

A **slot** is the app's stable identity (its name). It points at a series of AppConfigs,
one marked current.

- **On the box:** `apps/<name>/current.json` + `apps/<name>/history/<digest>.json`,
  replacing today's single `apps/<name>.json` + `prev_image`. The box can still stand
  alone.
- **In the console:** the `App` row is the slot and points at AppConfig versions, rather
  than holding the live config in a jsonb column.

Blue/green colors are not slots — they are one slot mid-cutover.

## Two timelines, kept apart

| Timeline | What it versions | Whose | Lives |
|---|---|---|---|
| App Library **`Version`** | the **code** (an image digest) | the publisher's | the App Library / manifest |
| AppConfig **artifact** | the **whole deploy spec** (image is one field) | the operator's, per slot | the slot's timeline |

A library `Version` bump is one reason to mint a new AppConfig; a hostname or env edit is
another. Keeping them apart keeps "update the code" and "change the config" separately
witnessed.

## Where the truth lives

- **The console owns desire.** Editing mints a new AppConfig version.
- **The box owns reality.** An observe read reports which digest is running.
- **Drift is digest ≠ digest** — two identities, no string diff.
- **Adopt is an explicit, witnessed act**, never a silent overwrite. So push and pull both
  exist without two writers on one document ([`two-records.md`](two-records.md)).

## Roads not taken

- **Config as a mutable jsonb blob on `App`** (today's shape). No identity, no timeline,
  no honest drift signal: rollback reconstructs, restore is special-cased, a box edit is
  invisible.
- **Reusing App Library `Version` for config versions.** One word for two things.
- **A floating "latest config."** A deploy names exactly the config it seats. "Current" is
  a pointer the slot holds, not a name resolved at apply time.

## Consequences

- Box layout moves to a per-slot timeline; folds into
  [`../blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md) when built.
- `App` gains a config-version timeline; folds into
  [`../blueprint/console/data-model.md`](../blueprint/console/data-model.md) when built.
- Accessories are fields inside the artifact, so they version with it
  ([`accessories-belong-to-one-app.md`](accessories-belong-to-one-app.md)).
