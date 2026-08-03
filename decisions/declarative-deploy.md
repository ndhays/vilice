# Declarative deploy + secret/env delivery

**Decided 2026-06-08.** Slice 1 (the core) is built and canonical in
[`blueprint/steward/deploy.md`](../blueprint/steward/deploy.md); this records the *why*
and the roads not taken. Supersedes the earlier "two imperative commands" sketch.

## Deploy is a declarative upsert, not an imperative run

`deploy` takes the app's **full desired state** and converges the box to it. No separate
`apply`, no incremental state — **first deploy == Nth deploy**, each self-contained.

- **Full-replace semantics.** The spec is the complete desired state; an omitted field
  is *removed*. Works because Steward Console's `Install` model always renders the full spec.
- **Self-contained.** Steward Console resends secret values each deploy (it holds them
  encrypted), so there is no set-once ordering and no dangling secret waiting for an app.

## The constraint that shapes the transport: argv is recorded, stdin is not

Every command is recorded (append-only, hash-chained, shipped off-host), so **a secret
must never ride the command line.** Steward is a forced command, so only
`SSH_ORIGINAL_COMMAND` (the arguments) is logged. The seam: the **spec + secret values
arrive as one JSON envelope on stdin**; `dispatch` records argv only. The recorded entry
is `deploy <app>` plus the **spec digest** = `sha256(canonical(app))` — the chain commits
to the exact spec (secret *names* included, values never), and the full readable spec is
persisted in app-state, verifiable against the digest.

A flag form (`--image/--hostname/--port/--health`) is kept for the simple, no-secret path.

## Secret store = Podman secrets

`podman secret create <app>__<NAME> -` from stdin → `run --secret <ref>,type=env,
target=<NAME>`. The value lives in *one* root-only place, not in `podman inspect` or the
container config; `podman secret ls` is a names-only ledger (mirrors `authorized_keys`).
Rotation = `rm`+create, which a redeploy does for free.

- **Secret-at-rest = root-only access control, not encryption.** Root (the ceiling) and
  the running container can read it; no scoped key, no other container, and no `steward`
  verb ever exposes a value. Encryption-at-rest only defends offline theft and needs an
  off-disk key (TPM / `systemd-creds`) — a later hardening, tied to god-key custody.
- **Steward stays app-agnostic.** It handles N named secrets; a Rails app declares one
  (`RAILS_MASTER_KEY`) and keeps the rest in `credentials.yml.enc` shipped in the image.
- **No new verb.** Rotation/lifecycle stay redeploy/`restart`; a "rotate" affordance
  lives on the Steward Console side, not in Steward.
- **Env *or* file (`secret_files`).** Same store, same stdin delivery, same never-recorded
  guarantee — only how the unit consumes the secret differs: `type=env,target=NAME` or
  `type=mount,target=/path`. Added for apps configured by a file (a registry's
  `config.json`, an htpasswd) rather than env vars; it needed no new store, transport, or
  verb, just a `name → path` map in the spec and a second `Secret=` line in the Quadlet
  unit. Mode/uid/gid stay defaulted (mount is `0444`, readable by the image's user) until
  an app needs otherwise.

## Roads not taken

- **Inline the whole spec JSON in the record entry** (vs the digest). The digest keeps
  the chain compact and unifies with the backup-tag scheme.
- **Root-owned `0600` `--env-file`** instead of Podman secrets. Kept only as a fallback
  for a box whose Podman is too old for `secret`; the `pass`/`shell` driver is the later
  encrypted-at-rest upgrade *without changing the deploy contract*.

## Where the rest lives

**Steward Console now drives this envelope** (Wave 3.2): `Install#deploy_envelope(image:)`
builds the `{app:{…}}` spec and the mutate ceremony pipes it on scoped-SSH stdin —
secret values still excluded (that panel is #14). See
[`open/ui-roadmap.md`](open/ui-roadmap.md) #12.

The Steward Console UI side (secret-by-default Environment panel) is in
[`console-open-questions.md`](open/console-open-questions.md). Remaining Steward
slices — `secret ls`/`rm` + status surfacing, backup exclusion + digest tagging,
encrypted-at-rest driver — stay open in
[`steward-open-questions.md`](open/steward-open-questions.md).
