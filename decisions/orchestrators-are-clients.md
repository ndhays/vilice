# Anything that orchestrates is a client

> Decided 2026-08-02.

## The decision

**Anything that orchestrates is a client, and clients act only through Vilice's command
surface.** An orchestrator holds a scoped key like the console, a person at a shell, a CI
job, or an AI agent. There is no privileged sidecar.

The mechanism is that there is nothing else to call. Vilice has no daemon, no listener
and no local API. The only way in is `_exec` behind an sshd forced command, and `_exec`
goes through `enter`, which writes the record before it dispatches.

## Why

Real operation needs sequencing — "deploy to A, wait healthy, deploy to B". The tempting
shape is an orchestrator on the box that drives Podman and Caddy directly and calls
Vilice to write a record entry.

That orchestrator is a path to the box's power that skips a named, scoped, recorded
invocation. Vilice would still write entries, but they would be a narration of the acts,
produced by the process that could narrate differently. A record that can be inaccurate
while looking complete is worse than none. It is the failure the interactive shell had
([`no-key-gets-a-shell.md`](no-key-gets-a-shell.md)).

## What it costs

- **Multi-box work is N scoped calls.** Each pays an SSH round trip, and there is no
  cross-box transaction: a sequence that fails halfway leaves the fleet halfway.
- **An orchestrator holds no state on the box** between calls. It observes by asking and
  acts by asking again.
- **A verb Vilice lacks is a verb the orchestrator cannot perform.** The pressure lands
  on the command surface.

The gain: **compromise the orchestrator and you get its scope, nothing more.**

## Roads not taken

- **An orchestrator daemon on the box.** Above.
- **A "trusted" scope that skips the record.** A scope nobody is supposed to use
  eventually gets used, and its existence qualifies the claim.
- **Vilice calls out to an orchestrator.** Then the decisions — which box, what order,
  whether to continue after a failure — are not acts in the chain; only their consequences
  are.
- **Let the console be special, since we write it.** A boundary its author may cross is
  not a boundary, and the console is the actor most likely to want the exception.
