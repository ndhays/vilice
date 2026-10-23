# Update is rollback pointed forward, and it runs in the background

> Decided 2026-10-23. Spec: [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md),
> "`vilice update`". Code: `vilice/internal/app/update.go`.

## What prompted it

Updating the deployed console meant building an envelope by hand on the box and pasting
all four of its secrets into it every time. The console stores those secrets nowhere —
it reads them from its environment ([`secrets-come-from-the-deployment.md`](secrets-come-from-the-deployment.md))
— so it could not send them itself, and a button on its Settings page was out of reach.

## The decision

**`vilice update <app> --image <ref@sha256:…>` re-applies the app's saved spec with only
the image changed.** It is exactly what `rollback` already does with the previous image:
load the spec the box holds, swap the image, run the deploy path. Secret values are not
sent, because they are already in Podman's store; nor is anything else, because it is
already in the spec. The new spec's digest is recorded before the box is touched.

**It runs in a transient systemd unit and answers at once.** `update` is the act —
recorded, then the request written beside the app's state, then the unit started.
`run-update`, system-scoped and so unreachable over scoped SSH, does the work, and runs
only a request still waiting. The outcome goes where `status` reports it.

## Why it is not a partial edit

`route` refuses add-a-route and drop-a-route because a partial edit needs the caller and
the box to agree about a starting state neither can see. `update` changes one field, but
the starting state is not guessed: it is the spec the box itself saved, the one `rollback`
already trusts. The caller names only what it is changing, and the box records the whole
resulting spec by digest. Anything more — a new env var, a volume — is a deploy, with the
whole spec, as before.

## Why in the background

When the console updates the console, the caller is the app being replaced. Blue/green
stops the old colour once the new one is healthy, and the old colour is the process
holding the SSH connection; a foreground deploy would lose its connection in the middle
of retiring that colour, and the console's record entry would never settle. A unit owned
by systemd finishes regardless. It is the same answer the release step gave for the same
reason: work that must not die with its caller is detached from it.

## Roads not taken

- **The console as an App of its own console**, deploying itself with stored secrets. It
  would have to store its own encryption keys inside the database they encrypt, and every
  update would send every secret — the thing this removes.
- **`deploy` without secret values, reusing the store.** A deploy is the whole spec;
  making its secrets optional would make "the box has what it needs" something a deploy
  silently assumed.
- **A `--detach` flag on `deploy`.** Any verb could then be asked to run unseen; an update
  is the one case that needs it, and it gets a name.
- **Double-fork and ignore SIGHUP.** Works until a child writes to the closed connection;
  a systemd unit has a name, a journal, and nothing to inherit.
- **The box finds the newest image itself.** The registry is private and the console holds
  no registry logins; a person names the digest
  ([`a-tag-is-not-a-release.md`](a-tag-is-not-a-release.md)).
