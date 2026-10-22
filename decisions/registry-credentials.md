# Private registry credentials — a box credential, not an app field

> Decided 2026-06-15. Companion to [`declarative-deploy.md`](declarative-deploy.md).
> Spec: [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md).

## The decision

**A standing box credential, set by a recorded command, never carried in the deploy
envelope.**

- `vilice registry-login <registry> --username <user>` — password on stdin, never argv.
  Runs `podman login` as `_vilice`, writing a persistent rootless auth file
  (`~_vilice/.config/containers/auth.json`, through `REGISTRY_AUTH_FILE`).
- `vilice registry-logout <registry>`.
- Both are operate scope and recorded: actor, action, registry and username. The password
  never is.

## Lifecycle — like `authorize`/`revoke`

A credential is shared by every app that pulls from its registry and outlives any one of
them.

- **Born** at `registry-login`; **dies** only at `registry-logout`.
- **Never removed by `remove`.** Apps A and B may share a registry; reaping it when A
  leaves would break B's next deploy.
- **Visible while it lives.** A standing credential nothing shows is ambient authority.
  `status` lists the registries (host and username); `doctor` reports which registries
  deployed apps reference and which have a login; the console shows them as a card on
  the machine page, with the acts on them
  ([`acts-sit-with-what-they-act-on.md`](acts-sit-with-what-they-act-on.md)).

## Failure handling

A wrong or expired credential surfaces at deploy time. That is bounded:

1. **Pull first.** `runDeploy` pulls before it touches a unit or route, so a failed pull
   changes nothing.
2. **Local-image short-circuit.** A digest already in local storage is not pulled. So
   restart, reboot recovery and rollback to a cached image work with an expired
   credential. The credential's blast radius is "bring a new image to the box".
3. **Classified errors.** `registry_auth` (401/403, retryable, names `registry-login`),
   `registry_unreachable` (retryable), `image_not_found` (not retryable).
4. **`doctor` warns early** about app registries with no login. It checks presence, not
   validity; a per-registry auth probe is deferred.
5. **Retention.** Rollback depends on the previous image staying in local storage, so
   prune must not collect `PrevImage` while it is the rollback target.

## v1: static credentials only

Username/password, PAT, htpasswd. AWS ECR and GCP Artifact Registry tokens expire in
hours and expect a credential helper — out of scope, tracked in
[`open/vilice-open-questions.md`](open/vilice-open-questions.md).

## Roads not taken

- **Credentials in the deploy envelope.** A registry credential and an app secret have
  different lifetimes. Carrying it per deploy mixes box state into every app's record.
- **Auto-logout on app removal, or refcounting.** Hidden coupling between apps. Orphans
  are surfaced, not reaped.
- **A credential as an app field.** Breaks when two apps share a registry.
