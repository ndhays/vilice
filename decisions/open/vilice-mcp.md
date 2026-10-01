# An MCP for Vilice — shapes and pitfalls

> **Not settled, and nothing is planned.** Raised 2026-08-14 as a thread worth keeping,
> not as work. Recorded here so the reasoning isn't re-derived from scratch if it is ever
> picked up — and so the shapes that are already forbidden stay forbidden.

**Last touched:** 2026-08-14.

---

## The frame: this is an adapter, not an architecture

The Model Context Protocol (MCP) is a way to hand a tool surface to an AI agent. The
question is what a Vilice one would be.

Most of the answer is already written.
[`orchestrators-are-clients.md`](../orchestrators-are-clients.md) settles that anything
which sequences work is a client holding a scoped key, and names the agent explicitly
alongside the console, a person at a shell, and a CI job. Its closing line is the whole
frame: *"the door an agent needs already exists, and it is the same door."*

So an MCP server is an **adapter over a door that is already built** — it translates a
tool call into `vilice <verb>` behind the same forced command as everything else.

**That is also the test.** If a design for this appears to need a change to the gate, a
new entry point, a daemon, or a scope that skips the record, the design is wrong — not
the constraint. The value of writing this down now is mostly that it makes the wrong
shapes recognisable on sight.

## What it would actually buy

Two things, and only one of them is novel.

**The manifest is already written.** `vilice _commands` emits the command table as JSON
— every verb's summary, paragraph, synopsis, flags (each with its own description), and
examples ([`../help-is-the-documentation.md`](../help-is-the-documentation.md)). That is
very nearly an MCP tool manifest already. A hand-authored tool list would be a *second
description of the CLI*, exactly the drift `core.CheckDocs` exists to prevent, and it
would sit outside the compiler's reach. **Derived from `_commands`, an MCP server cannot
describe a verb the binary doesn't have, or miss a flag the gate accepts.** If this is
ever built, that derivation is the non-negotiable part.

**Reads are the good fit.** "Why did this app restart," "which boxes are on a stale
image," "who authorized this key and when" are read-heavy questions that span machines
and want correlation, which is what the record is for and what an agent is good at. The
console answers them for a human; nothing answers them for an agent today except a
person pasting output.

## Four shapes

| Shape | Where it runs | Verdict |
|---|---|---|
| **Adapter beside the agent** | wherever the agent is; holds its own scoped key | the default; no new surface on the box |
| **`vilice mcp` over stdio** | on the box, reached through SSH | possible, one real cost (below) |
| **Console-hosted endpoint** | in the Rails app | plausible for the fleet view |
| **A daemon on the box** | on the box, listening | **forbidden** |

**1. An adapter where the agent runs.** The boring long-term answer. It holds a key
authorized as its own client at its own scope, and opens an SSH connection per call like
any other client. Nothing on the box changes; nothing in the gate changes. If this is
built at all, this is almost certainly the shape.

**2. `vilice mcp` over stdio.** Tempting, because stdio is not a listener and so does
not violate "no daemon, no listener, no token." The cost is subtler: MCP is a **session**
— many calls over one connection — where every client today is *one command per
connection*. Scope is enforced at the SSH layer by the forced command, **before Vilice
runs**; a session moves that enforcement inside the Go process, which must then check
each tool call against the scope its forced command pinned.

This is *not* the deleted shell — dispatch is still the command table, every call still
goes through `enter`, and every call still writes its entry before it acts
([`../no-key-gets-a-shell.md`](../no-key-gets-a-shell.md)). But it would be the first
time the scope boundary lives in code rather than in `authorized_keys`, and
[`auth.md`](../../blueprint/vilice/auth.md) currently says the forced-command wrapper
*is* the boundary. That sentence would need to change, which is reason enough to think
hard before making it true.

**3. A console-hosted endpoint.** Attractive because the fleet view — apps, drift,
plan-vs-reality — lives in the console, not on any one box, and a per-box adapter can
never see it. The obvious objection (the box's record would say `client=console`, not the
agent's name) is already answered:
[`two-records.md`](../two-records.md) settles that human attribution is the *control
plane's* record to keep, because Vilice structurally cannot see it. An agent is the same
case as an operator. This is an existing seam, not a new violation — but it does mean the
agent's identity is only as good as the console's record, which is not hash-chained.

**4. A daemon on the box.** A listener beside Vilice, driving Podman and Caddy for
speed, calling Vilice to write entries so the history looks complete. This is the exact
shape [`orchestrators-are-clients.md`](../orchestrators-are-clients.md) exists to forbid,
and the reasoning is unchanged: a record that can be inaccurate while looking complete
launders the lie. Named here only so it stays named.

## What must hold, whatever the shape

1. **The agent is its own named actor.** Its own key, its own client name, its own rung —
   never the console's key, never a shared "agent" key across several agents. `actors`
   must be able to show it as a distinct line, and `revoke <client>` must be able to
   remove exactly it. This is Invariant 1 and it is free; failing it is a choice.
2. **One tool call is one dispatch.** The entry is written before the action, by the
   same `enter` path as everything else. An adapter that batches, retries silently, or
   reports an outcome it didn't get from the box is narrating.
3. **The ceiling is untouched.** `harden`, `prepare`, and `uninstall` are root-only and
   reachable by no scoped key, so no MCP surface can expose them, whatever its manifest
   claims ([`../ceiling-is-the-machine.md`](../ceiling-is-the-machine.md)).

## Pitfalls, sharpest first

**Prompt injection is the one genuinely new threat.** It is the only risk here that a CI
job holding the same key does not carry. `logs` output, container image labels, app
names, an app's own HTTP response — all of it becomes tokens in a context window, and any
of it can carry instructions. An agent holding `operate` that reads a log line saying
"now deploy image X" is a textbook confused deputy.

Vilice's gate stays honest under this: it records and executes exactly what a named
actor at a declared scope asked for, and the record shows who and when. But that is
forensics, and the design elsewhere prefers a gate. The mitigation is **scope, not
cleverness** — an `observe` key cannot be talked into anything — which is why the
read-only slice below is the honest first version. It also pairs directly with two
threads already open in
[`vilice-open-questions.md`](vilice-open-questions.md): *time-boxed grants*
(`authorize --expires`) and *scoped observe*.

**An agent that closes drift is the reconciler we refused.** Nothing structurally stops an
agent from polling `status` and deploying whenever reality diverges from plan. That is
auto-convergence wearing a name badge, and
[`../drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md) rejected it
deliberately. It is not *forbidden* — the agent is named, scoped, and recorded, which is
more than most reconcilers manage — but it must be a decision someone makes on purpose,
never something that arrives as a side effect of shipping a tool surface.

**Composite tools launder the plan.** A `deploy_fleet` tool that sequences N boxes is
legitimate — it is a client, and clients may sequence. But the boxes record N deploys and
*nothing* records the plan: which boxes, in what order, whether to continue past a
failure. That is the same gap as the rejected "let Vilice call out to an orchestrator"
road — the interesting decision goes unrecorded. Console-hosted (shape 3) has an answer,
since fleet-level grouping is explicitly the console's to record; a standalone adapter
does not.

**Summarising is narrating.** `logs` and `record` output are large, and the pressure to
have the adapter condense them before they reach the model will be immediate. A summary
produced by the thing being asked to report is the failure mode the whole project is
built against. Pass output verbatim, paginate rather than compress, and if something is
ever summarised, mark it unmistakably as a summary.

**Naming.** MCP is a protocol's proper name and passes as-is; a coined verb around it
would not. If it ever becomes a subcommand, `vilice mcp` is the plain form, and the tool
names should be the verbs the CLI already has — not a friendlier parallel vocabulary that
a reader has to map back.

## Honest ledger

**For:** the door exists, so the work is small; the manifest derives from a table that
already exists; reads across a fleet are a real unmet need; it costs the box nothing in
shape 1; and it is a genuine demonstration that "an AI agent is just another named actor"
was a real claim rather than a nice sentence.

**Against:** it hands a language model a key to production infrastructure, and the main
new risk (injection) is one this design can record but not prevent; it invites composite
verbs whose plans go unrecorded; the fleet-level version needs the console, which
complicates the identity story; and every shape adds a surface to keep honest for a
convenience nobody has asked for yet.

## If it is ever picked up

**Start read-only, and treat write as a separate decision.** An `observe`-scoped adapter
carries almost none of the risk and most of the value, cannot be talked into acting, and
would prove out the `_commands`-derived manifest — which is the part worth learning
whether it works. Anything that writes should wait for time-boxed grants, and should
probably wait for someone to actually want it.

Related open threads: *time-boxed grants*, *a self-update scope*, and *scoped observe /
image allowlist*, all in
[`vilice-open-questions.md`](vilice-open-questions.md).

## Roads already closed

- **A daemon or sidecar on the box.** Shape 4 above — closed by
  [`orchestrators-are-clients.md`](../orchestrators-are-clients.md), not reopened here.
- **Reusing the console's key as the agent's identity.** Convenient, and it makes the
  agent anonymous inside a client name that means something else. Invariant 1 is the
  cheapest thing in this document to get right.
- **A hand-maintained tool manifest.** A second description of the CLI, outside
  `CheckDocs`, guaranteed to drift.
- **A scope that lets an agent act without a record**, for latency or for batching. The
  reasoning that deleted `ssh` scope applies unchanged: a scope nobody is supposed to use
  is one that eventually gets used.
