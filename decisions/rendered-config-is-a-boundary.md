# Rendered config is a boundary

> Decided 2026-08-01, from a security audit. Mechanism: `validateState` /
> `validateRenderable` / `validHostname` / `looksLikePubkey`, and the fuzz targets in
> `internal/core/inject_test.go` and `internal/app/render_inject_test.go`.

## The problem

Nothing a caller sends reaches a shell: `SSH_ORIGINAL_COMMAND` is split into named
arguments, secrets ride stdin, and every host-side `bash -c` interpolates only Vilice's
own constants. Command injection was closed.

Config injection was open. Three line-oriented formats, all built by string
interpolation:

- **The Caddy fragment.** A hostname containing a newline writes whole site blocks.
- **A Quadlet unit.** A volume string containing a newline adds any directive —
  `PodmanArgs=--privileged`, `AddCapability=…`.
- **`authorized_keys`.** A "public key" containing a newline writes a second line with no
  forced command and no restrictions: a shell grant.

In a line-oriented format, a value that can end its own line can write the next
directive.

## The decision

**A value is validated before it is rendered, and the validation is an allow-list.**

- No control character reaches any rendered file.
- A hostname must look like a site address — optional scheme, optional `*.`,
  letters/digits/dots/hyphens, optional port (`validHostname`).
- A public key is one line: known type, base64 blob, at most a comment
  (`looksLikePubkey`).
- An app name is `[A-Za-z0-9_-]` and may not begin with a dash — it is passed to `podman`
  and `systemctl` as an argument, where a leading dash reads as a flag. Checked at the
  door for every command whose synopsis says `<app>`, not per command, which is how five
  lifecycle verbs missed it.

**Allow-list, not block-list.** The first fix rejected newlines, braces and whitespace in
a hostname. The fuzzer broke it in under a minute with `#`: a hostname of `#` comments out
its own site's opening line and breaks routing for every app on the box. A block-list
needs you to have thought of the character.

## Bind mounts are confined

An `operate` key could step over the scope ladder two ways. A volume of `/:/host:rw`
bind-mounted the host filesystem into a container, where
`~_vilice/.ssh/authorized_keys` is writable — and writing that file is a grant. A hostile
restic repo reached the same file through `restore --target /`.

- **Bind-mount sources live under a declared root** (`/srv` by default,
  `VILICE_BIND_ROOTS` to change it). Named volumes are unrestricted; Podman keeps them
  inside `_vilice`'s own storage.
- **A restore is confined with `--include`** to the app's declared volumes and its spec
  file. restic puts absolute paths back where the snapshot says, so an unbounded
  `--target /` lets whoever controls the repo write anywhere `_vilice` can.

## Two tiers of check

- **Rendering safety** — can this value end its own line? `validateRenderable`, checked
  **everywhere**: the doors, `saveApp`, `writeUnit`, `refreshCaddy`. It applies to state
  read back off disk too.
- **Policy** — may this app ask for this? Where a bind mount may live, and (since
  2026-10-05) a wildcard hostname over HTTPS, which the box can route and cannot get a
  certificate for until it does DNS challenges.
  `validateState` (renderable + policy), checked only where a spec **enters** the box: a
  deploy and a restore.

Checking policy at render time was the first version and was wrong: tighten the
bind-mount rule and every box with data at `/data` stops routing anything. Checking it on
the way in is enough, because exploiting it means introducing a hostile volume, and those
two doors are the only way.

`loadApp` validates neither: an app whose spec no longer passes should fail loudly at its
next deploy, not vanish from `status`. A test pins this — an app with a legacy bind mount
still renders, persists and routes, and is refused only on redeploy.

## Roads not taken

- **Escaping instead of refusing.** Each format has its own escaping rules, and Go's `%q`
  is not OpenSSH's. Refusing is one rule.
- **Validating only at the CLI door.** Wrong for rendering safety: specs also arrive from
  restic snapshots and files on disk.
- **One validation function for everything.** Shipped first; it made every policy rule
  retroactive to installed apps.
- **Dropping bind mounts** (named volumes only). Some apps want a path visible from the
  host; confining to a root gives the same safety.
- **A block-list of dangerous characters.** Above.
