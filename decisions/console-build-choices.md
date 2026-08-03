# Steward Console — Build Choices (first cut)

**Decided 2026-06-03**, building the first cut of the Rails app. The data model's
three inline decisions (tenant boundary, key custody, read strategy) are settled in
`blueprint/console/data-model.md`; this records the choices made *around* them.

## Auth = Rails 8 built-in, not Boxcar `Person`

Operators sign in with the **Rails 8 authentication generator** (`User` + `Session`,
`has_secure_password`, signed cookie). Steward Console's operators are a few internal,
trusted humans — battle-tested web auth is the right tool, and it's the "keep
battle-tested web auth" the platform overview already calls for.

Boxcar's `Person` generator was **not** used: it models domain identities (residents,
officials) under the constitution, not application logins. `Current.actor` is aliased
to the signed-in user so Boxcar's accountability fallback works when we reach for it.

## Boxcar applied with restraint

Boxcar is loaded and Steward Console is "built on" it, but in this cut only **`Identifiable`
on `Project`** (`identifies :entity` — Article I: a Project *is* the client entity) is
wired. `Stateful` (on `InstallTarget`), `Eventable` (broadcasting into `Event`), and
the `View` recording stack are **deferred**, not rejected.

Why: Boxcar's own rule — *if you cannot point to the article that requires a line, it
does not belong*. Forcing `Attributable`'s mandatory-immutable-actor onto every row, or
`Stateful`'s declared-transition machine, before the mutate flow is real would be
ceremony. `Event.actor` is a plain string on purpose: it carries Steward's record actor
(a client name) as easily as a Steward Console user's email. Revisit when the mutate side
grows beyond the single `apply-updates` demonstrator.

## solid_cache lives in the primary DB in dev/test

Decision 3 says observe reads cache in solid_cache. Production keeps a **separate cache
database** (`config/database.yml`); dev and test run a **single** database, so the
`solid_cache_entries` table is migrated into the primary DB and `config.cache_store =
:solid_cache_store` in development matches production's store. A cache miss just
re-reads Steward — the on-box record stays the source of truth.

## The heartbeat proof was retired

The one-button proof that Rails could reach a box is gone, replaced by the real Home
journey and the per-machine observe panel. Its transport survives: shell out to system
`ssh`, parse `--json`, now per-`Machine` with the encrypted key materialized to a 0600
tempfile for the length of one call.
