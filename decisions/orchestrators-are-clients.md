# Anything that orchestrates is a client

> Decided 2026-08-02. Nothing sequences work on a box from
> beside the door: an orchestrator holds a scoped key and comes through Vilice's
> command surface like every other actor.

## The question

Real operation needs sequencing — "deploy to box A, wait healthy, deploy to box B."
Something has to hold that logic. The tempting shape is a small orchestrator binary
*on the box*, running with its own privileges: it drives Podman and Caddy directly
because that is fast and convenient, and calls Vilice to write a record entry so the
history still looks complete.

That shape is the one thing this design cannot survive.

## The decision

**Anything that orchestrates is a client, and clients only ever act through Vilice's
command surface.** The orchestrator holds a scoped key like everyone else — the
console, a person at a shell, a CI job, an AI agent. It is not special, and there is
no privileged sidecar.

The mechanism is that there is nothing else to call. Vilice has no daemon, no
listener, and no local API. The only way in is `_exec` behind an sshd forced command,
and `_exec` goes through `enter` — the same single door as the local CLI — which writes
the record before it dispatches. A would-be orchestrator has no second entrance to use,
which is why this is mechanism and not policy.

## Why the convenient shape is fatal

The whole claim is *un-bypassability*: there is no path to the box's power that skips a
named, scoped, recorded invocation ([`blueprint/vilice/overview.md`](../blueprint/vilice/overview.md)).
An orchestrator that touches Podman and Caddy itself **is** that path. Vilice would
still be writing entries, but the entries would no longer describe the acts — they would
describe a narration of the acts, produced by the same process that could choose to
narrate differently.

That is strictly worse than having no record, because a record that can be inaccurate
while looking complete **launders** the lie. It is the same failure the interactive
shell had ([`no-key-gets-a-shell.md`](no-key-gets-a-shell.md)): the record showed that
something began, and nothing about what it did. Vilice becomes a log file with extra
steps — exactly the thing it was built not to be.

## What it costs

Sequencing happens off-box, which is a real constraint, not a free one:

- **Multi-box work is N scoped calls, not one privileged agent.** Each call pays SSH
  round-trip latency, and there is no cross-box transaction — a sequence that fails
  halfway leaves the fleet halfway, and the recovery is another sequence of named calls.
- **An orchestrator cannot hold state on the box** between calls, or react in-process to
  something it observes. It observes by asking, and acts by asking again.
- **A verb Vilice does not have is a verb the orchestrator cannot perform.** Pressure
  lands on the command surface being good enough. That is the direction the design
  already wants to be pushed.

The gain is the pitch: **compromise the orchestrator and you get its scope, nothing
more.** That sentence is only true because the orchestrator never held anything else.

## Roads not taken

- **An orchestrator daemon on the box.** The shape above. Rejected as the thing that
  ends the claim.
- **A "trusted" scope that skips the record**, for the orchestrator only. A scope nobody
  is supposed to use is one that eventually gets used, and its mere existence puts the
  asterisk back on the claim — the reasoning that deleted `ssh` scope applies unchanged.
- **Invert it: let Vilice call out to an orchestrator.** Then the orchestrator's
  decisions — which box, which order, whether to continue after a failure — are not acts
  in the chain, only their consequences are. The interesting part goes unrecorded.
- **Let the console be special**, since we write it. Rejected precisely because we write
  it: a boundary that its author may cross is not a boundary, and the console is the
  actor most likely to want the exception.

## What this answers preemptively

"Where does fleet logic live?" — In a client, off the box, holding a scoped key. The
console is one such client and gets no privilege the CI job or the agent does not. That
is what makes an agent-facing pack a small piece of work rather than a rearchitecture:
the door an agent needs already exists, and it is the same door.
