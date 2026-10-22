# App Library — a manifest, not a second database

> Decided 2026-06-14. Companion to [`open/app-library.md`](open/app-library.md).

## The decision

**A YAML manifest (`Library` PORO + `app_templates#export`/`import`), one SQLite
database.**

- **Export** flattens apps and their versions to a manifest Hash → YAML.
- **Import is additive:** apps upsert by `name`, versions by `tag`; nothing is deleted.
  Two vendor libraries merge and coexist.
- **Bulk remove** (`app_templates#remove_selected`) is the only way the library shrinks,
  recorded as one act.
- The DB is the runtime store; the manifest is the interchange shape. Import takes a file
  or a URL (`Library.fetch`).

The library is convenience and legibility, **not a security boundary** — that stays the
box's image rules and the scoped operate key.

## Roads not taken

- **A separate SQLite database for the library.** Feasible: `App` references the library
  only through nullable snapshot links. Rejected because `Label` is polymorphic (shared
  with Machine/Project) and could not follow without splitting, and cross-DB joins would
  break the list's search. A flat file is more portable than a sidecar `.sqlite3` anyway.
- **Labels in the manifest.** Labels are the admin's local organization; the manifest is
  the publisher's definition. Exporting them leaks a private taxonomy; importing them lets
  a vendor dictate your filing. Official categories, if ever needed, are a separate field.
- **A record entry per imported app.** A 100-app import would smear the record. One
  `imported library` event carries the count and source in `summary` and every app name in
  `detail` — still reconstructable.
