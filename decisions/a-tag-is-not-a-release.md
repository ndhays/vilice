# A tag is not a release, so the console resolves it once and never again

> Decided 2026-08-18. Spec:
> [`blueprint/console/data-model.md`](../blueprint/console/data-model.md) (`Version`).
> Pairs with [`registry-credentials.md`](registry-credentials.md).

## The decision

**The console may look a digest up for you. It may never follow a tag for you.**
Resolution is a read; pinning is a decision.

*Look up digest* asks the registry what `ghcr.io/acme/web:v1` points at now and puts the
answer in the field. It saves nothing and records nothing. Adding the version is a
separate press, with the digest on screen first. Nothing re-resolves afterwards.

## Why

The box refuses an unpinned image, and `Version` mirrors that. A tag means something
different tomorrow. A `Version` that stored `web:v1` and resolved it at deploy would
record *deployed v1* while what ran is unrecoverable, and rollback would have no "image
that was running" to return to. The record would still look complete — the same failure as
a reconciler closing a gap
([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)).

## Public registries only

[`registry-credentials.md`](registry-credentials.md) put registry logins on the box, so
the control plane holds no pull access to private images. The lookup therefore reaches
public registries anonymously, with a `pull` token scoped to the one repository. When a
registry asks for a credential it stops, names `vilice registry-login`, and offers the
paste-it-yourself path.

A registry credential in the console would be a new class of secret in the privileged
layer, bought for a convenience ([`ceiling-is-the-machine.md`](ceiling-is-the-machine.md)).

## Roads not taken

- **Store the tag, resolve at deploy.** Makes *what was running* unanswerable.
- **Store both, re-resolve on a schedule.** The release would change with no one
  deciding, and the entry would name no actor.
- **Resolve on save, without showing the digest.** One less press, and it removes the
  decision.
- **Registry credentials in the console.** Above.
- **A JS-driven lookup.** A second submit with `formnovalidate` does it with no
  JavaScript.

## Still open

Listing which tags exist is not built. When `latest` moves, nothing notices; surfacing
that as an offer is in [`open/what-could-go-wrong.md`](open/what-could-go-wrong.md).
