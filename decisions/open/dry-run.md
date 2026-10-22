# A dry run — asking the box "would this work?"

> **Not settled, and nothing is built.** Raised 2026-10-03, checking Vilice against four
> tests for software an agent can drive: machine-readable output, clear exit codes, a
> dry-run flag, and narrow permissions. It passes three. This is the fourth.

---

## Where Vilice stands on the four

- **Machine-readable output — passes.** Every verb takes `--json` and returns one shape
  (`code`, `retryable`, `message`, and `data` for reads), over about thirty named codes.
  `vilice _commands` describes the whole command table.
- **Narrow permissions — passes.** A named key at a scope, no shell, a ceiling no key
  reaches, every act recorded under its actor before it runs
  ([`../../blueprint/vilice/auth.md`](../../blueprint/vilice/auth.md)). Scopes are per
  box, not per app; that is its own thread in
  [`vilice-open-questions.md`](vilice-open-questions.md).
- **Exit codes — pass, coarsely.** `0` / `1` / `2`. See "Related" below.
- **A dry run — fails.** There is no way to ask what a verb would do without doing it.

## What exists today, and why it is not this

- **`deploy` validates every field before it writes anything**
  ([`deploy.md`](../../blueprint/vilice/deploy.md)), so a bad spec is refused cleanly —
  but the only way to learn that is to attempt the deploy, with an operate key, as a
  recorded act.
- **`harden --check`** reads the box's posture. It reports what *is*, not what a change
  would do.
- **The console's ceremony** previews the exact command it will send. That is a preview
  of the request, not of the box's answer.

## The questions

### 1. A flag, or a verb?

`deploy --dry-run` is the familiar shape. But the gate decides what a key may run from
the **command's name** — scope is a column in the command table, and `decideExec` is a
pure function of it. A flag that changes what a command *is* (a write at operate scope,
or a read) puts a second axis into the one place that is deliberately table-driven.

The alternative is one read verb that takes the act as its argument — the envelope on
stdin exactly as `deploy` reads it — so the table stays the whole truth: one name, one
scope. Verbs are forever ([`../the-name-is-vilice.md`](../the-name-is-vilice.md)), so
the name has to be plain and right the first time. Not decided: the shape, or the word.

### 2. What does "would work" cover?

Three depths, and each costs more than the last.

- **The spec is valid.** Pure: the field rules, the port floor, the names every container
  would get, the role (a balancer runs no apps). No box state read, nothing touched.
- **This box can take it.** Reads the box: the hostname is free here, the app is not busy,
  every declared secret would have a value, the box holds a login for the image's
  registry. Still changes nothing.
- **The world agrees.** The image exists at that digest; the app would come up healthy.
  The first means asking a registry. The second cannot be known without running it, and
  a dry run that claimed it would be lying. **Pulling is out**: it changes the box's
  image store, and a check that leaves bytes behind is not a check.

The answer should also say **what would change**: which color, which routes, or
*nothing* when the spec's digest is the one already running. A caller wants the diff as
much as the verdict.

### 3. At what scope?

A check that changes nothing could be an **observe** act. That is the interesting
property: an agent holding a read-only key could validate a deploy without holding the
power to do one, and a person could approve what it checked.

Three things stand in the way, and the third is real.

- **Secret values ride the envelope.** A check must need names only, or discard values
  unread; an observe key should never be a reason to send a secret.
- **Does it reveal anything?** Whether a hostname or an app name is taken is already in
  `status`, which observe can read. Nothing new there.
- **The registry check is an oracle.** Asking a private registry "does this image exist"
  uses the *box's* login. At observe scope that hands a read-only actor a way to probe
  registries it has no credentials for. So either the world-depth check stays at operate,
  or it is left out.

### 4. Is it recorded?

By the standing rule, no: reads are not recorded, and
[`../a-sample-is-not-an-act.md`](../a-sample-is-not-an-act.md) keeps the record to acts.
The case for recording it anyway is the agent case — "it checked three times before it
acted" is worth knowing. The case against is that a record full of questions buries the
answers. Lean: not recorded, like every other read.

### 5. The gap between the check and the act

A dry run is not a reservation. The box can change between the check and the deploy, and
`deploy` must validate again regardless. What ties the two together is the **spec
digest**: the check should return it, and the record entry for the deploy already
carries it — so "this is the spec that was checked" is provable after the fact, without
the check holding anything.

### 6. Which verbs, in what order

`deploy` first — it is where a wrong answer costs most and where the spec is richest.
Then `route` (the table would be validated the way Caddy validates it), `remove` and
`restore` (what would be lost), and `apply-updates` (apt can already simulate).

## A trial — the other half (raised 2026-10-05)

Everything above is a **check**: it changes nothing, so it may not pull an image and may
not promise health. That leaves the question an operator actually asks before placing an
app on a box — *will it come up here?* — unanswered on purpose. A **trial** answers it,
and it is a different thing: it is an act.

### What it is

Pull the image, start the app beside whatever is live, wait for its health path, and stop
there. Traffic is never switched to it. Then take it down and say how it went.

`deploy` already does this as its first half: the new color comes up on its own port,
is health-checked, and only then does Caddy flip
([`deploy.md`](../../blueprint/vilice/deploy.md)). A trial is that sequence stopped
before the flip, followed by the teardown a failed deploy already runs. So it needs
little new machinery, and "never goes live" is a property the deploy path has today.

### How it differs from the check

| | Check | Trial |
|---|---|---|
| Changes the box | no | yes — pulls an image, runs a container, then removes it |
| Says | the spec is valid and this box could take it | it pulled, started, and answered its health path |
| Scope | could be observe | operate |
| Recorded | no, like every read | yes, before it runs, like every act |
| Leaves behind | nothing | the pulled image, until the next prune |

They are two verbs, not one verb with a depth flag, for the reason in question 1: the
gate decides from the command's name, and these sit at different scopes.

### What it must not do

- **Run the release step.** A migration changes real data. A trial of an app that
  declares one starts the app without it and says so in its answer — which means a trial
  cannot vouch for an app that will not boot until its schema is there.
- **Touch the app's live volumes.** A second copy writing to the first copy's data is
  the thing blue/green is careful about. Not decided: start it with no volumes, with
  empty throwaway ones, or refuse to try an app that declares any.
- **Start or restart accessories.** An accessory already running is left alone, as in a
  deploy. One that is not running is not brought up for a trial — not decided whether
  the trial then proceeds without it or stops.
- **Stand in for the deploy.** Like a check, it is not a reservation. `deploy` pulls (or
  finds the image cached), starts, and health-checks again.

It still needs every declared secret's value, on stdin, as a deploy does.

### "Deployable" is a dated fact, not a status

The tempting shape is a green *deployable* on a Library version. Two things are wrong
with a standing status:

- **It is true of a version on a box, not of a version.** Whether the image can be pulled
  depends on that box's registry login; whether it boots depends on that box's secrets
  and settings.
- **It goes stale.** A credential expires and the status is still green.

What holds is the record entry the trial writes: *tried on nick-main, 5 Oct, this
digest, came up healthy*. The console shows that on the version — a check with its box
and its date — and on the box when placing. The state is the latest thing the record
says ([`../ui-shape.md`](../ui-shape.md)); nothing is stored that the record does not
already hold. The digest ties it to the deploy that follows, as in question 5.

### What it is for: placing a known app

This came out of asking when the console should have a button at all
([`ui-roadmap.md`](ui-roadmap.md)). The lean there is that the console sends acts on
**things it holds a definition for** — an App Template and its version — and only names
the rest. Under that rule every deploy starts from the Library, including a second
placement of an app already running elsewhere, and a trial is what makes "place it on
this box" a press someone can make with a reason to expect it to work.

### Open

- The word. `try`, `trial`, `rehearse`. Verbs are forever.
- Volumes and accessories, above.
- Whether the pulled image is kept (a later deploy then needs no pull, and no working
  registry credential) or removed (a trial leaves the box as it found it). Lean: kept —
  the image store is a cache, and prune already owns it.
- Whether a failed trial's logs are returned the way a failed deploy's now are.
- Build order against the check. The trial is nearer to hand, since the deploy path
  already contains it; the check is the one with the agent-facing property.

## What must stay true

- **No new entry point.** It comes through the same forced command as every verb
  ([`../orchestrators-are-clients.md`](../orchestrators-are-clients.md)).
- **A check writes nothing** — no unit, no secret, no image, no record entry for an act
  that did not happen.
- **A check never promises health.** It says what it checked, and that is all it says.
- **A trial never takes traffic**, and is recorded like any act.

## Related: exit codes

Every failure exits `1`; whether to retry is only in the JSON (`retryable`). A caller
reading only the exit status cannot tell `app_busy` from a refusal. A distinct status for
retryable failures would fix that. Small, separate, and it changes a contract callers may
already depend on, so it is written here rather than done in passing.

## What the answers change

- *A trial* → the console can show, on a Library version and when placing, where and
  when that digest last came up healthy; and the machine page's free-form deploy can
  give way to "add it to the Library, then place it".
- *A read verb at observe scope* → the console's ceremony can show the box's own answer
  before the press, not just the command — which is most of "what a command does on the
  box" in [`ui-roadmap.md`](ui-roadmap.md) — and an MCP adapter
  ([`vilice-mcp.md`](vilice-mcp.md)) gets a tool an agent can call freely.
- *A flag at operate scope* → simpler to build, and it gives up the property that makes
  this worth more than a convenience.
