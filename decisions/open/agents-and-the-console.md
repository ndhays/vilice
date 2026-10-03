# Agents and the console — who proposes, who approves

> **Not settled, and nothing is built.** Raised 2026-10-03, from one question: if an AI
> agent does the operating, how does a person stay in charge? It would change
> [`../what-the-console-is-for.md`](../what-the-console-is-for.md), which is settled, so
> it starts here. The box-side shapes an agent can take are in
> [`vilice-mcp.md`](vilice-mcp.md); this is about the console's part.

---

## The question

An agent drives the CLI as well as a person does
([`../orchestrators-are-clients.md`](../orchestrators-are-clients.md)). So acts will come
from agents. Three things were considered for what that makes of the console, in the
order they were raised.

## 1. The console holds no operate key at all

Observe only; every act is done by an agent or by hand.

**Gains.** The console stops being the keys to the fleet: today its database holds a key
that can deploy to and remove from every box, plus each app's secret values, and whoever
holds the console holds all of it. The confirm step, the deploy forms, the stored secrets
and the pending/settled events all go. And it matches a line already written — *"Running
commands is not on the list… the console should not compete."*

**Costs.** It deletes the third thing the console is for — **bounded acts**, a button a
non-expert can press. The witnessed confirm step goes, with nothing in its place. A human
name on an act goes too: the box records only the key's name, and the console is what adds
the person ([`../two-records.md`](../two-records.md)). And the intention layer — an app,
its count, its placements, a balancer's table — has no one left to send it.

**A middle form:** the console *composes* and does not *send* — forms and preview stay,
and the page ends with the exact command and spec to run elsewhere.

## 2. The console's operate becomes a gate

The better idea, and smaller than it sounds: the confirm step is already *approve or deny
this exact command*. Today the command always comes from a form. Let an agent compose it.

1. The agent holds an **observe** key. It reads everything and can change nothing.
2. To act, it files a **proposal**: the exact command and spec.
3. The proposal lands in the Status inbox, which exists to show what needs a person
   ([`../status-is-an-inbox.md`](../status-is-an-inbox.md)).
4. A person sees the preview and presses **Approve** or **Deny**. Both are recorded.
5. On approve, the act runs.

That keeps the witnessed step, the human name, the intention layer and bounded acts — and
an agent that cannot act cannot be talked into acting. The worst a poisoned log line can
do is put a bad proposal in the inbox.

### Two places the gate can live

- **In the console.** The console sends the approved command with its own operate key.
  Mostly the existing ceremony, plus an inbox and a way to file. The honest cost: the
  gate is the console's code, the console still holds every operate key, and the box's
  record says only *console*. Who proposed and who approved are in the console's record,
  which is not hash-chained. No worse than today; none of the gain in (1) either.
- **On the box.** The agent files the proposal *on the box* with its observe key. The
  console's key can only approve what has been proposed; it cannot originate an act.
  Neither key acts alone — a two-key rule the box enforces — and the box's own record
  carries both lines. New verbs on the box, and verbs are forever
  ([`../the-name-is-vilice.md`](../the-name-is-vilice.md)).

The first can be built now and the second is where it should end up. Not decided:
whether to build the first at all, or wait for the second.

### What must hold, in either place

- **What is approved is exactly what runs.** The approval names the spec's digest, so
  nothing can change between the two. Proposals expire. This is the same digest a dry run
  would return ([`dry-run.md`](dry-run.md)) — and a dry run is what makes approving mean
  something, because the screen can show the box's answer, not only the command.
- **The approval screen shows the command, never the agent's account of it.** A summary
  can be wrong, or steered by something the agent read. *Summarising is narrating.*
- **Approving takes more than a logged-in session.** A passkey on the Approve button: the
  proof comes from the person's device, so nothing running on the server — the agent
  included — can produce it. This is the mechanism that makes "a person approved" true
  rather than assumed.
- **The agent has no way round.** It never holds an operate key of its own. If it does,
  the gate is a suggestion.
- **Deny is an act too**, recorded with who and why.

## 3. Where the agent runs

**Outside, holding its own observe key** — the default in [`vilice-mcp.md`](vilice-mcp.md).
The box enforces the limit. But it sees one box at a time and never the fleet.

**Against a console endpoint (MCP).** The fleet view — apps, placements, drift, the
merged record — lives in the console, and a console-hosted endpoint is the only shape
that can show it to an agent. The console offers *read* and *propose* tools; the operator
brings whatever agent they already use. The tool list should come from what the console
can already do, the way an on-box adapter's would come from `vilice _commands`.

**Embedded: a chat in the console.** Possible, and the proposals would land where they
are approved. Three costs:

- **The limit becomes code.** An outside agent is bounded by a key the box checks. An
  agent inside the app that holds the operate keys is bounded by its tool list. The two
  rules above carry the weight then: no tool it has reaches a box, and Approve needs a
  passkey the server cannot forge.
- **Data leaves.** Status, app names and logs go to a model provider, and logs can hold
  secrets. For a tool about servers you control, that is opt-in, off by default, with the
  operator's own key — or it contradicts the thesis.
- **It is a product.** A chat surface, a tool loop, streaming, model upgrades, cost — on a
  console whose stated job is watching.

**Lean:** the gate first; then the endpoint; an embedded chat only as one more client of
the same tools, if it is still wanted after using the first two.

## What a person can do today, with no code

- **Give the agent an observe key.** It investigates and writes the exact command.
- **Keep the operate key on a hardware key** (`sk-ssh-…`, which `authorize` already
  accepts) that needs a touch per use. Vilice opens one SSH connection per command, so
  **one touch is one act** — and the agent may even run the command, because it blocks
  until a person touches the key.
- **Without hardware,** `ssh-add -c` makes the SSH agent ask before each use. Weaker — it
  is software on the same machine — and free.

An agent's own permission prompts are a useful layer and not the control: they are a
setting on the agent's side, and the box does not enforce them.

## What else it leans on

- **Time-boxed grants** (`authorize --expires`, in
  [`vilice-open-questions.md`](vilice-open-questions.md)) — a person hands an agent
  operate for half an hour and it removes itself. In charge of *when*, not of *each*.
- **Per-app scopes** — an agent that may redeploy one named app.
- **A dry run** ([`dry-run.md`](dry-run.md)) — see above.

## What the answers change

- *The gate, in the console* → `what-the-console-is-for.md` gains a line rather than
  losing one: bounded acts stay, and "who composed it" stops being assumed to be the
  person pressing the button. The console needs a proposals model, an inbox entry, a way
  for an agent to file, and passkeys.
- *The gate, on the box* → new verbs and a new rung or pair of rungs on the scope ladder
  ([`../../blueprint/vilice/auth.md`](../../blueprint/vilice/auth.md)), and the console
  can hold a key that approves and nothing else — which is (1)'s gain, kept.
- *No operate in the console* → the decision above is rewritten, and most of the console's
  write side is removed.
