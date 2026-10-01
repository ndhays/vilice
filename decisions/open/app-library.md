# Steward Console — App Library (open items)

> The App Library is **built and graduated**: the operator-facing flow is in
> [`blueprint/console/journeys.md`](../../blueprint/console/journeys.md), the model
> (`AppTemplate → Version`, the three-tier `AppTemplate → App → Placement`, the manifest) in
> [`blueprint/console/data-model.md`](../../blueprint/console/data-model.md), and the
> manifest *why* in [`../app-library-manifest.md`](../app-library-manifest.md). What remains
> here is the **governing principle** and the open items.

**Last touched:** 2026-06-16.

---

## The governing principle: two separate layers

These are **different features on different layers**, not two answers to one question — and
keeping them apart is the point. It explains why the allowlist below is a separate, open,
Steward-side item rather than a property of the (built) library.

- **Steward Console App Library — bookmarking / curation.** Built. A directory the admin curates;
  saved definitions used to install quickly and consistently. A convenience layer. **Not a
  security boundary.**
- **Steward image allowlist — security.** Separate, simple, maybe later. The box refuses any
  image not on an authorized allowlist (`authorized_keys`, but for images) —
  **un-bypassable**. Its own Steward-side feature + decision. The `apps_library_only`
  setting *may* later be backed by it for real teeth, but the two ship independently.

Convenience lives in Steward Console; un-bypassability lives on the box (the scoped `operate` key
is the real ceiling today — a key-holder can `steward deploy <any-image>` directly).

## Open

- **Env value-half (#14-B) — built 2026-08-19.** `App#secret_values` is encrypted at
  rest and resent on every deploy, `deploy_envelope` carries
  `secrets`/`secret_files`/`secret_values`, and the values are supplied on the app's
  own page (`apps#configure`) rather than in the create form — a value is not part of
  an intention, and the declared names depend on the app chosen a step earlier. The env
  schema sits on the **App**, as planned. *Still open here:* per-version overrides, and
  the dropped `default` / `required?` fields. See
  [`console-open-questions.md`](console-open-questions.md).
- **Image granularity** — repo-level (any digest from `ghcr.io/acme/web`) vs. digest-level.
  Lean repo-level + digest-pinned deploys for v1.
- **Global vs. per-project** library — lean global v1; per-project later (multi-tenant).
- **Registry tag discovery**, version notes / yank. Resolving *one* tag to its digest is
  built — **Look up digest**, `Registry.pin`, and the rule it follows is
  [`a-tag-is-not-a-release.md`](../a-tag-is-not-a-release.md). What is still open is
  listing which tags a repository *has*, and noticing when `latest` moves — which must
  arrive as an offer, never an update, for the same reason.
- **Marketplace** — a shared, online library index (`applibrary.agoraforge.org`).
  Import-from-URL is built (`Library.fetch` + the Import menu); the **index** is what's
  missing, plus an *official* manifest field for categories (separate from local labels).
  Hardening note: `fetch` is admin-only/admin-trusted and does **not** yet refuse private
  address ranges (SSRF).
- **Seed from a repo manifest** — a checked-in `db/library.yml` that seeds installs.
  Deferred; a local library file is gitignored for now (share via the marketplace).
- **Demo library + harness — built, threads paused (2026-06-15).** `examples/library.yml`
  (10 apps) and the integration-test app `examples/harness-rails/` are committed. Paused: a
  **Node twin** (`examples/harness-node/`), a **websocket `/ws` drain** endpoint, **digest-
  pinning** the library images, and a **seed convenience** to load `examples/library.yml`. A
  Steward gap surfaced: the health gate is HTTP-only, so pure-TCP services (Postgres/Redis)
  can't deploy — see
  [`vilice-open-questions.md`](vilice-open-questions.md).
- **The Steward allowlist itself** — whether/when it lands, and whether
  `apps_library_only` then drives it.
