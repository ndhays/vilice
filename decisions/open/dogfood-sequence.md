# The Dogfood Sequence — Steward Console deploys Steward Console

> The ordered plan for making the control plane run *itself*, smallest real loop first. Each
> step is a commit-sized slice with its own blueprint/decisions sweep. This doc is the
> **plan-of-record for the ordering**; the *why* of each mechanism lives in the decisions it
> links. Retire it once step 3 lands (the model is then proven, not planned).
>
> **Opened:** 2026-07-31.

---

## Why this order

The goal is **Steward Console-deploys-Steward Console** — the real test of the whole model, because the
control plane is just another app it should be able to place, redeploy, and roll back. Getting
there has a natural dependency order: the config Steward Console mints today is the *stateless,
secretless* subset of the AppConfig, so the two missing keys in `Install#deploy_envelope` —
`volumes` and `secrets` — are the literal prerequisites, and they fall in that order because
**state** (a volume) is what a redeploy would otherwise lose, while **secrets** are what any
*other* real app needs first.

Each step is sized to the three build-safe rules (`CLAUDE.md`): one concern, observable, and
reversible.

## The sequence

### 1. Volume field on the `Install` — **done (this slice)**

`Install#deploy_envelope` carries `volumes`; the field is declared on the install
(`config.volumes`), validated against the box's `Volume=` format, and surfaced on the new/show
pages. Closes the "self-hosting needs a volume field on the install" gate in
[`console-open-questions.md`](console-open-questions.md). The fork it resolved — a
Steward Console-only special volume vs. a general per-install field — landed on the **general** field.
See [`data-model.md`](../../blueprint/console/data-model.md) (`Install`).

*Left as residue, not blockers:* volume-name uniqueness on a shared box, and any extra protection
for Steward Console's own volume (never pruned on `remove`).

### 2. Secret / env UI → `deploy_envelope` carries `secrets`

The other missing key. `deploy_envelope` today omits secret *names*, and there is no off-record
channel for their *values*. This slice: surface declared secrets on the install (names in the
config, mirroring `App`'s declared inputs), carry the names into the envelope, and wire the
value channel that keeps values off the record (the box's `Secret=type=env` — env vs secret is
"one flag", per [`data-model.md`](../../blueprint/console/data-model.md)). **Unblocks any real
app**, since almost every app needs at least one secret. Ties to the off-record value channel
open thread in [`console-open-questions.md`](console-open-questions.md).

### 3. Stand Steward Console up on one box and have it redeploy itself

The payoff. With volumes + secrets in the envelope, Steward Console is now a fully-expressible app.
Install it onto a box, then drive a redeploy of itself *through itself*. This **proves the
model** end-to-end and flushes the genuinely open gap: **where the observe key really lives** when
the thing being redeployed is the redeployer (the self-update floor —
[`console-open-questions.md`](console-open-questions.md) "You never need Steward Console to
update Steward Console", and genesis of the control plane). Pairs with the Steward floor: a scoped key
or the console is always the break-glass, so the in-app self-drive is convenience, never a
dependency.

### 4. Accessories — the next real app (Rails + Postgres)

The first app that needs a *companion* container, not just persistent state. Builds the
`accessories` block inside the AppConfig artifact (shared Podman network + container-DNS + stable
aliases, accessories outliving app redeploys). Design already in scope —
[`steward-open-questions.md`](steward-open-questions.md) "Accessories" and
[`deploy-config-model.md`](deploy-config-model.md). This is the step that turns "runs a
single-container app" into "runs a normal web app", and it comes *after* dogfooding because
Steward Console itself doesn't need an accessory to stand up.

---

Feeds: [`console-open-questions.md`](console-open-questions.md) (self-hosting, secrets,
genesis) and [`deploy-config-model.md`](deploy-config-model.md) (the missing AppConfig keys).
As each step lands, migrate its truth into [`blueprint/`](../../blueprint/) and a
[`decisions/`](../) note, and strike it here.
