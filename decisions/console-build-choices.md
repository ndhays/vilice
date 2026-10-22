# Vilice Console — build choices (first cut)

> Decided 2026-06-03. The data model's own decisions are in
> [`blueprint/console/data-model.md`](../blueprint/console/data-model.md).

## Auth is the Rails 8 generator, not Boxcar `Person`

Operators sign in with `User` + `Session`, `has_secure_password`, signed cookie. They are
a few trusted humans, and standard web auth fits. Boxcar's `Person` models domain
identities under the constitution, not logins. `Current.actor` is aliased to the signed-in
user so Boxcar's accountability fallback works.

## Boxcar applied with restraint

Only `Identifiable` on `Project` is wired. `Stateful` (on `Placement`), `Eventable`, and
the `View` recording stack are deferred, not rejected. Boxcar's own rule: if you cannot
point to the article that requires a line, it does not belong. `Event.actor` is a plain
string on purpose — it carries a box record's client name as easily as a user's email.

## solid_cache lives in the primary DB in dev/test

Production keeps a separate cache database; dev and test run one database with
`solid_cache_entries` migrated into it, so the store matches production. A cache miss
re-reads Vilice; the box's record stays the source of truth.

## Transport

Shell out to system `ssh`, parse `--json`, per `Machine`, with the encrypted key written
to a `0600` tempfile for the length of one call.
