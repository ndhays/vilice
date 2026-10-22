# The core is handwritten, and hosted apart

> Decided 2026-08-05, after Codeberg's members voted to amend the Terms of Use.

## The problem

Codeberg's members voted (358–144, closing 2026-07-22) to add § 2 (1) 7:

> You must not share projects that mostly consist of code written by "generative AI"-tools
> (including services such as *Claude*, *OpenAI Codex*).

Most of the Go and the Rails here was machine-written. "Mostly" is a real qualifier, but
arguing where the line falls is ignoring the rule with extra steps.

## The decision

1. **The Vilice core is rewritten by hand, and that rewrite goes to Codeberg.**
   Reimplemented from the blueprint, not transcribed.
2. **Everything else lives where the clause does not apply** — today
   `github.com/ndhays/vilice`. The README and the site say outright that what is
   published is a proof of concept, most of it machine-written.
3. **An LLM may review, never author.** The human writes the test and the
   implementation; the model reads and argues. Nothing it produces enters the repo.

## Why a rewrite

An earlier design rejected a rewrite as re-deriving code "for no gain". There are now
three gains.

**Copyright — the durable one.**

- **Can others claim our code?** Generated code can reproduce training data. Retyping
  does not cure that. Implementing from a specification largely does, because independent
  creation is the defence.
- **Can we own it?** The US Copyright Office requires human authorship. **You cannot
  license what you do not own**, and a copyleft over largely unownable code is weak. For a
  project about sovereignty, that is a hole in the thesis.

**Every line is validated.** "I wrote and understand every line of the gate" is a
stronger claim than any amount of review.

**Go fluency**, on the code where it matters.

**The risk that survives:** un-bypassability lives in the absence of paths, and absence
does not port. A reimplementation can reintroduce a path. The Go tests, `audit/`, gosec
and the gate tests carry over as the specification of what must stay absent.

## Transcribing versus reimplementing

Copying the old file line by line changes nothing legally. Reimplementing from
`blueprint/` — prose that is canonical and came first — is re-projecting from the source.

The existing code may be used as an **answer key, after the fact**. Facts and ideas are
free: *Caddy rejects an empty config*, *validate before writing*. Expression is not:
comment prose, error wording, identifier names, the decomposition into functions. Write
first, compare second.

## The spec stays whole, with the console

The rule that the blueprint changes in the same commit as the behaviour cannot hold
across a repo boundary. So the spec is not duplicated and not split. Only the handwritten
core leaves, and its spec section ([`../blueprint/vilice/`](../blueprint/vilice/)) is
self-contained enough to work from at a distance. The cost: a behaviour change and its
blueprint update land in two repos, held together by discipline.

## The release key rule is about providers

`install.sh` fetches the release public key from a **different provider** than the one
that serves the binary, so no single compromised account supplies a matching key and
binary. A shared control plane is a shared provider: two hostnames under one DNS zone and
one Cloudflare account can be re-pointed by one credential.

Today: the key on Codeberg (`codeberg.org/vilice/vilice`), the binary from
`get.vilice.org`, the source on GitHub. Nothing an install fetches comes from GitHub
([`the-name-is-vilice.md`](the-name-is-vilice.md)). A public key is not AI-written code,
so that repo is outside the clause. It must stay publicly readable.

**Failure modes.** Compromise Codeberg alone: installs get a wrong key, verification
fails, nothing installs. Compromise the release host alone: the signature does not match.
An attacker needs both. `PUBKEY_FILE` is the only way past a Codeberg outage, on purpose.

## What it costs

- **Time.** Several thousand lines of Go plus tests, written test-first.
- **The console is not rewritten**, and its provenance is unchanged.
- **Two hosts to keep in step** once the core moves.

## Roads not taken

- **Ignore the rule.** The project's subject is accountability.
- **Argue "mostly."** Defensible arithmetic, indefensible posture.
- **Move everything to a forge that permits it.** [Tangled](https://tangled.org/) is the
  best: no such clause, portable identity, self-hostable storage. Rejected for now
  because it is VC-funded, and terms follow funding. GitHub solves the rule and
  contradicts the thesis, which is why it holds the source and nothing an install depends
  on.
- **Serve the key from a self-hosted forge.** One DNS zone and one Cloudflare account
  would govern both — a shared provider.
- **Serve the key from GitHub, beside the source.** One account could change both what a
  release is built from and the key that vouches for it.
- **Keep the code on Codeberg and host the tests elsewhere.** The tests are internal
  (`package core`, `package app`) and test unexported identifiers, so Go needs them
  beside the source. And a trust core published without its tests is a worse artifact.
- **Rewrite the Rails console too.** The same copyright gain at triple the cost, on the
  half nobody has to trust. Deferred.

## Still open

- **The console's provenance.** An AGPL over largely machine-written Rails is as thin as
  it was.
- **Where release tooling lives** once `vilice/` is its own repo.
- **A first hand-written verb as a trial.** `vilice route`: about 200 lines, a written
  spec, an existing test suite.
