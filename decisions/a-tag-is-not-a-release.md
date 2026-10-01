# A tag is not a release, so the console resolves it once and never again

> Decided 2026-08-18, building **Look up digest** on the App Library. The canonical
> *what* is [`blueprint/console/data-model.md`](../blueprint/console/data-model.md)
> (`Version`); this is the *why* and the roads not taken. Pairs with
> [`registry-credentials.md`](registry-credentials.md), which decided where a registry
> credential lives, and takes the same shape as
> [`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md).

## The question

The box refuses an unpinned image, and `Version` mirrors that refusal so it fails where
you type it. That rule is right and it is not moving. But it has one genuinely unpleasant
consequence: to add a release you must go and find 64 hex characters, by hand, in another
tool.

The obvious fix is to let the library hold a tag. Most registries' own tooling works that
way, and it is what people ask for.

## The decision

**The console may look a digest up for you. It may never follow a tag for you.**

One sentence carries it:

> **Resolution is a read; pinning is a decision.**

*Look up digest* asks the registry what `ghcr.io/acme/web:v1` points at right now and
**puts the answer in the field**. It saves nothing, records nothing, and creates nothing.
Adding the version is the same press it always was, and the digest you are about to store
is on screen before you press it.

Nothing re-resolves afterwards. Ever.

## Why the convenient shape is fatal

A tag means something different tomorrow. That is not a footnote about registries — it is
the reason the pin exists at all. A `Version` that stored `web:v1` and resolved it at
deploy would produce a record saying *deployed v1* while what actually ran is
unrecoverable, and rollback would mean nothing, because "the image that was running" would
have no answer.

That is the same failure as a reconciler closing a gap: the system quietly changes what a
recorded decision meant. Here it would be worse than a bad record, because the record
would still *look* complete.

The mechanical statement of it: **the two steps are visible on purpose.** A person sees
the digest, then decides. A flow that resolved-and-saved in one press would be the same
feature with the decision removed, and the decision is the part that matters.

## Public registries only, and that is the boundary working

[`registry-credentials.md`](registry-credentials.md) put registry logins **on the box**, so
that pull access to your private images is not something the control plane holds. This
feature does not get to quietly reverse that.

So the lookup reaches public registries, anonymously — it requests a `pull` token scoped to
the one repository being looked at, which obtains nothing anyone else could not. When a
registry asks for a credential, it stops and says so, naming `vilice registry-login` and
offering the paste-it-yourself path.

Adding a registry credential to the console would be a new class of secret in the
privileged layer, bought for a convenience. That is a raised ceiling
([`ceiling-is-the-machine.md`](ceiling-is-the-machine.md)) and the trade is not close.

## Roads not taken

- **Store the tag, resolve at deploy.** The shape above. Rejected as the thing that makes
  *what was running* unanswerable. A seed comment in the repo described this design as
  though it were built, which is how the question surfaced — the code had always refused
  it.
- **Store both, and re-resolve on a schedule to keep the digest current.** This is
  auto-convergence wearing a different hat: the release would change without anyone
  deciding, and the entry that recorded it would name no actor.
- **Resolve on save, without showing the digest first.** Same outcome, one less press, and
  it deletes the moment the whole design exists to preserve.
- **Registry credentials in the console**, so private registries work too. Rejected above.
- **A JS-driven lookup.** It would be smoother and it would fail closed on a form whose
  field pattern demands a digest. A second submit with `formnovalidate` does the job with
  no JavaScript at all, and a guard that refused to let you *ask* for the value it demands
  would be a strange guard.

## What it still does not do

Discovering **which tags exist** is a different feature and is not built — this answers
"what does this tag point at", not "what tags are there". When `latest` moves in the
registry, nothing notices; surfacing that as an **offer** (never an update) is the
version-drift note in
[`decisions/open/what-could-go-wrong.md`](open/what-could-go-wrong.md), and it would follow
this same rule.
