# Declarative deploy + secret/env delivery

> Decided 2026-06-08. Spec: [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md).
> Supersedes an earlier "two imperative commands" sketch.

## Deploy is a declarative upsert

`deploy` takes the app's full desired state and converges the box to it. First deploy and
Nth deploy are the same call.

- **Full replace.** An omitted field is removed. Works because the console always renders
  the whole spec.
- **Self-contained.** The console resends secret values each deploy, so there is no
  set-once ordering.

## Argv is recorded, stdin is not

Every command is recorded, so **a secret must never ride the command line.** Only
`SSH_ORIGINAL_COMMAND` is logged. The spec and secret values arrive as one JSON envelope
on stdin. The recorded entry is `deploy <app>` plus the spec digest,
`sha256(canonical(app))` — secret names included, values never. The readable spec is kept
in app state and can be checked against the digest.

A flag form (`--image/--hostname/--port/--health`) stays for the no-secret path.

## The secret store is Podman secrets

`podman secret create <app>__<NAME> -` from stdin, consumed as `type=env,target=<NAME>`.
The value is not in `podman inspect` or the container config; `podman secret ls` lists
names only. Rotation is remove-and-create, which a redeploy does.

- **At rest it is access control, not encryption.** The store's owner and the running
  container can read a value; no scoped key, other container, or Vilice verb exposes one.
  Encryption at rest defends offline theft and needs an off-disk key (TPM,
  `systemd-creds`) — later.
- **Vilice stays app-agnostic.** It handles N named secrets.
- **No new verb.** Rotation is redeploy; a "rotate" control belongs in the console.
- **Env or file (`secret_files`).** Same store and delivery; `type=mount,target=/path`
  for apps configured by a file. Mount mode stays the default (`0444`) until an app needs
  otherwise.

## Roads not taken

- **Inline the whole spec in the record entry.** The digest keeps the chain compact and
  matches the backup tags.
- **A `0600` `--env-file`** instead of Podman secrets. Kept only as a fallback for a
  Podman too old for `secret`.

## Still open

`secret ls`/`rm`, status surfacing and an encrypted-at-rest driver are in
[`open/vilice-open-questions.md`](open/vilice-open-questions.md).
