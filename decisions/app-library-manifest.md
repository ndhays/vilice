# App Library — a manifest, not a second database

**Decided 2026-06-14.** How to make the App Library importable / exportable and
separable from the rest of the data model. Companion to
`decisions/open/app-library.md`.

## The question

The App Library should be easy to share, version, and seed — and it should read as
"official" (the publisher's app definitions), distinct from an admin's local
organization. How should that portability be built, and how separable from the main
data model does it need to be?

## What we chose

**A YAML manifest (`Library` PORO + `apps#export`/`import`), one SQLite database.**

- **Export** flattens apps + their versions to a manifest Hash → YAML.
- **Import is additive**: apps upsert by `name`, versions by `tag` (image refreshed);
  nothing is deleted. Two vendor libraries (`abc.yml`, `acme.yml`) merge and coexist.
- **Bulk remove** (`apps#remove_selected`, multi-select on the list) is the deliberate
  counterweight to additive import — the only way the library shrinks, recorded as one
  act.
- The DB stays the runtime store; the manifest is the **interchange** shape — the form a
  marketplace (`applibrary.agoraforge.org`) would publish. Import takes a file **or a
  URL** (`Library.fetch`), so a published manifest can be pulled straight in.

## Roads not taken

- **A separate SQLite database** for the library (Rails multiple-databases). *Feasible* —
  `Install` already references the library only through **nullable, snapshot** links
  (`app_id`/`version_id`, `dependent: :nullify`, with the image digest copied at install
  time), so the library is already detachable at runtime. **Rejected** because the cost
  outweighs the win: `Label` is polymorphic (shared with Machine/Project), so it can't
  follow the library into a second DB without splitting it; and cross-DB `joins` would
  break the list's search. A manifest gives the portability (a shareable, git-able,
  seedable file) without the second-database tax — and a flat file is *more* portable than
  a sidecar `.sqlite3` anyway.

- **Labels in the manifest.** **Rejected.** Labels are the admin's *local* organization
  (`env=prod`, `mine`); the manifest is the publisher's *official* definition. Exporting
  labels would leak a private taxonomy when sharing, and importing them would let a vendor
  dictate your filing. Official categorization, if a marketplace ever needs it, is a
  *separate* field — never aliased onto local labels.

- **A record entry per imported app.** **Rejected.** A 20–100-app import would smear the
  append-only record. Instead one `imported library` event carries the count + source in
  `summary` and every app name in `detail` — still fully reconstructable (the
  accountability invariant), without the row spam. (Import is instantaneous — no per-app
  `pending → ok` outcome to settle, so nothing is lost by collapsing it.)

## Why this is true to the thesis

The library is **convenience + legibility, not a security boundary** (that stays the
Steward image allowlist + the scoped operate key). A portable, additive, hand-curated
manifest fits that: it makes the easy path easy for assistant admins without pretending to
be a wall. Pruning is explicit and recorded; merging is cheap and reversible.
