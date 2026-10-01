# Private registry credentials — a box credential, not an app field

**Decided 2026-06-15.** How Steward pulls from a private (authenticated) image
registry, where that credential lives, and how it fails. Companion to
`decisions/declarative-deploy.md` (secrets) and `blueprint/vilice/deploy.md`.

## The question

A deploy pulls a digest-pinned image. Public images just work; a private one needs
a credential. Where does that credential live, what is its lifecycle, and what
happens when it's wrong or expired at deploy time?

## What we chose

**A standing box credential, set by a recorded command, never carried in the deploy
envelope.**

- `steward registry-login <registry> --username <user>` — **password on stdin**, never
  argv. Runs `podman login` as the steward user, writing a **persistent** rootless
  auth file (`~steward/.config/containers/auth.json`, via `REGISTRY_AUTH_FILE` set in
  the user-context exec seam so login, pull, and logout all share it across reboots).
- `steward registry-logout <registry>` — the explicit counterweight.
- Both are **operate**-scope, so dispatch records them: actor + action +
  `<registry>` + `--username` land in the record; **the password never does** (same
  stdin-not-argv discipline as deploy secret values).

### Lifecycle — modeled like `authorize`/`revoke`, not like a deploy artifact

A credential is a standing resource shared by every app that pulls from its registry
and outliving any one app. So:

- **Born** at `registry-login`. **Dies** only at explicit `registry-logout`.
- **Never** removed as a side effect of `remove` — apps A and B may share one
  registry; reaping it when A leaves would silently break B's next deploy.
  Refcounting infra credentials against apps is exactly the hidden coupling to avoid.
- **Observable while it lives** (a standing credential nothing surfaces is ambient
  authority — fails the legible-ceiling invariant): `status` lists the registries the
  box is logged into (**host + username, secrets redacted**); `doctor` reports which
  registries the deployed apps reference and which have a login; Steward Console mirrors
  this as an Access-style ledger on the machine page.
- **Not app-owned.** The app→registry link is *derivable* (image → registry → is the
  box logged in?) and worth surfacing as a warning, but the credential is never a
  field on the app.

### Failure handling — the decoupling's blast radius is bounded

Because the credential is decoupled from the app, an expired/wrong credential
surfaces at deploy time, not login time. That's safe by construction:

1. **Pull-first, fail-safe.** `runDeploy` pulls before it touches any unit or route, so
   a failed pull leaves the running app untouched — "nothing changed". A re-deploy
   after expiry is a loud no-op, the live app keeps serving.
2. **Local-image short-circuit.** We pull only when the digest isn't already in local
   storage. Digest-pinned images are immutable, so a present one is the right bits.
   This keeps **restart, reboot recovery, and rollback-to-a-cached-image working even
   with an expired credential** — the credential's blast radius is exactly "introduce a
   *new* image to the box", nothing more.
3. **Classified, actionable errors.** A pull failure is parsed into a result code:
   `registry_auth` (401/403/expired → "run `steward registry-login <registry>` and
   redeploy", retryable), `registry_unreachable` (network, retryable), or
   `image_not_found` (bad digest, not retryable). Steward Console surfaces the auth case as
   "the box's credential for `<registry>` looks expired → refresh", pointing back at
   the box credential.
4. **Doctor early-warning.** `doctor` flags app registries with no login before the next
   deploy. Caveat: it checks login **presence**, not token **validity** — a
   present-but-expired static token still passes (you can't know it's dead without a
   registry round-trip). An optional per-registry auth probe could close that; deferred.
5. **Retention.** Rollback's credential-independence depends on the previous image
   staying in local storage — whatever prune policy lands must not GC `PrevImage` while
   it's still the rollback target.

### v1 boundary — static credentials only

Username/password, PAT, or htpasswd registries (GHCR PAT, Docker Hub, self-hosted
zot). **AWS ECR / GCP Artifact Registry tokens expire in hours** and expect a
*credential helper*, not a static `auth.json` — a different mechanism. Out of scope for
v1; tracked in `decisions/open/vilice-open-questions.md`. Doctor's coverage check
partly mitigates a rotted static token (it shows up as "registry not logged in").

## Roads not taken

- **Per-deploy creds in the envelope** (alongside `secret_values`). Rejected: a
  registry credential and an app secret have different lifetimes, so different homes. A
  credential is standing infra shared across apps; smearing it across every app's deploy
  record conflates infra with the app and bloats the record. Registry auth is box state,
  like an SSH host key.
- **Auto-logout on app removal / refcounting.** Rejected — shared credential, see
  lifecycle above. Pruning is deliberate and recorded; orphans are surfaced, not reaped.
- **A credential as an app field.** Rejected — couples shared infra to one app and
  breaks when two apps share a registry.

## Why this is true to the thesis

The credential lives where its lifetime says it should (the box), is born and dies
through **named, recorded** acts (invariant 1 + 2), and stays **legible** — `status`,
`doctor`, and the machine-page ledger make standing authority visible rather than
ambient (invariant 3). The deploy envelope stays about the *app*, not the
*infrastructure it pulls from*.
