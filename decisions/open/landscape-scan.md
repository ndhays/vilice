# Is this already solved, and better?

> The question that gates everything else, unanswered.

---

> **One of them is audited.** Kamal is the nearest neighbour and now overlaps enough to
> compare properly — see [`kamal-audit.md`](kamal-audit.md). It does not answer the
> question below (Kamal is not the same shape: it deploys *your* app and keeps a
> convenience log, where this keeps a record). It does find two things worth taking and
> one place Vilice may have chosen wrong.

## The question

Two things need **disconfirming** evidence, and the honest answer to any of them may be
"stop":

1. **Is the shape already shipped?** A single dependency-free binary, agentless and
   daemonless, driving an existing box over SSH to deploy containers. Not the self-hosting
   PaaS category — that is crowded and we know it — but this exact shape.

2. **Is the record genuinely unoccupied?** Checked in three places, not one: self-hosting
   tools; access/session management (Teleport, Boundary, StrongDM, Tailscale SSH — which
   record *sessions*, a different claim from recording *authorized actions before they
   run*); and supply-chain provenance (sigstore, in-toto, SLSA, Rekor), where a
   transparency log may already be the standard answer and may make an on-box chain
   redundant rather than complementary.

The third question — does the name collide? — is answered: it did, and the name is now
Vilice ([`../the-name-is-vilice.md`](../the-name-is-vilice.md)).

## What the answers change

- *"This exists and is better"* → a `decisions/` entry for the road not taken, and a hard
  conversation about whether to continue.
- *"The record angle is unoccupied"* → it becomes the headline of the site and the project,
  not a feature on page two.
