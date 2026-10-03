# The core is handwritten, and hosted apart

> Decided 2026-08-05, after Codeberg's members voted to amend the Terms of Use. Splits the
> project across hosts on purpose and changes how the core gets written.

## The question

Codeberg's members voted (358–144, closing 2026-07-22) to add § 2 (1) 7 to the Terms of
Use:

> You must not share projects that mostly consist of code written by "generative AI"-tools
> (including services such as *Claude*, *OpenAI Codex*).

This project is squarely inside that. Every commit carries a `Co-Authored-By` trailer for
an LLM, and the great majority of the Go and the Rails was machine-written. The word
"mostly" is a real qualifier and a real exemption for projects with occasional
assistance — but reaching for it here would mean arguing about where the line falls, which
is the same posture as ignoring the rule with extra steps.

Two things were true at once: the rule applies to us, and we did not want to be the kind of
project that looks for daylight in it.

## The decision

**Three parts.**

1. **The Vilice core is rewritten by hand, and that rewrite goes to Codeberg.** Not
   transcribed — *reimplemented from the blueprint*, which is the distinction that does all
   the work (below).
2. **Everything else lives where the clause does not apply** — today
   `github.com/ndhays/vilice`. What is on Codeberg must be the rewrite, not a promise of
   one, so the repository as it stands cannot be there. Both the README and the docs site
   say so outright: what is published is a proof of concept, most of it machine-written,
   with the handwritten core as the stated intention. A reader should not have to infer
   provenance from commit trailers.
3. **An LLM may review, never author.** The clause bans code *written by* generative AI. It
   says nothing about using one to critique code a human wrote, and that is the arrangement
   from here: the human writes the test and the implementation, the model reads them and
   argues. Nothing it produces enters the repo.

## Why a rewrite, when one had already been rejected

An earlier design rejected starting a new repo with this one as reference, and it was right
*on its premise*: a rewrite "re-derives exactly the code least worth re-deriving … for no
gain." **The operative words were "for no gain."** There are now three, and the first is the
one that would still matter if the vote were reversed tomorrow.

### Copyright — the real driver

Two separate questions hide under "copyright," and the unfamiliar one is the one that bites.

- **Can others claim our code?** Generated code can reproduce something memorised from
  training data. The risk is low for idiomatic Go and higher for distinctive algorithms.
  Retyping does **not** cure it — copyright does not care about the keyboard. Implementing
  from a specification largely does, because independent creation is the actual defence.
- **Can *we* own it?** The US Copyright Office position is that human authorship is
  required: purely machine-generated output is not protectable, and AI-assisted work is
  protectable in its human-authored parts. **You cannot license what you do not own.** The
  project offers MIT for Vilice and AGPL for the Console, and a copyleft over
  largely-unownable code is a weak instrument. For a project whose entire pitch is
  sovereignty and capture-resistance, an unenforceable licence is a hole in the thesis, not
  a technicality.

So the copyright argument runs *toward* handwriting, which is the opposite of how it first
looked. It is also the durable reason: hosting terms change, and this does not.

### The other two gains

- **Every line is validated.** The core is the part a skeptical reader must trust. "I wrote
  and understand every line of the gate" is a stronger claim than any amount of review.
- **Go fluency**, on the code where it matters most.

### What survives from the old rejection

One clause, and it is not about economy: *"un-bypassability lives in the absence of paths,
which does not port."* A reimplementation can reintroduce a path the current code does not
have. This is the thing to watch, not a veto — the Go tests, `audit/`, gosec, and the
verb-surface guard all exist to catch exactly that, and they carry over as the
specification of what must remain absent.

## Transcribing versus reimplementing — the distinction the plan rests on

Copying the old file line by line while reading it would achieve understanding and nothing
legal: the provenance is unchanged, and independent creation is hard to claim about
something you were looking at.

Reimplementing from `blueprint/` is a different act, and this project is unusually well
placed for it. The blueprint is prose that is canonical and came first — the doc model's
own words are "code is a projection of this." So writing Go from it is not
reverse-engineering an implementation; it is re-projecting from the authoritative source.
That is about as clean as a solo reimplementation gets.

**The reference implementation may be used as an answer key, after the fact.** Facts and
ideas are free — *Caddy rejects an empty config*, *validate before writing so a refusal
leaves the previous fragment*, the existence of a standard-library call. **Expression is
not**: comment prose, error-message wording, identifier names, the particular decomposition
into functions. The order is what keeps this honest — write first, compare second.

## Why the spec travels with the console, not the core

The awkward part of splitting one project across two hosts is that `CLAUDE.md`'s strictest
rule — the blueprint changes *in the same commit* as the behaviour — cannot hold across a
repo boundary. Drift is the failure mode this project guards hardest against.

Duplicating the shared spec was rejected outright: two copies of the canonical truth is the
exact fiction the doc model exists to prevent. Splitting `blueprint/vilice/` away from the
rest was considered and dropped — several decisions genuinely span both halves
([`one-primitive-composed.md`](one-primitive-composed.md),
[`console-layers.md`](console-layers.md)), and cross-links would break.

So the spec stays whole, with the console. **The handwritten core is the only thing that
leaves**, and it is the one piece whose spec section
([`../blueprint/vilice/`](../blueprint/vilice/)) is self-contained enough to work from at
a distance. The cost is real and accepted: a behaviour change in the Go and its blueprint
update land in two commits in two repos rather than one, and nothing but discipline keeps
them together.

## The rule for the release key is about providers

`install.sh` fetches the release public key from a **different provider than the one that
serves the binary**, so no single compromised account hands you a matching key and binary.
The rule is not "the key lives on Codeberg" — it is **different providers**, and a shared
control plane counts as a shared provider: two hostnames on separate servers but under one
DNS zone and one Cloudflare account can be re-pointed together by one credential.

Today the key is the only thing on Codeberg (`codeberg.org/vilice/vilice`), the binary
comes from `get.vilice.org`, and the source is on GitHub — three providers, with nothing an
install fetches coming from GitHub ([`the-name-is-vilice.md`](the-name-is-vilice.md)). **A
public key is not AI-written code**, so a repo holding one is outside the clause. The repo
must stay **publicly readable**: the installer's fetch is unauthenticated and runs on a
stranger's box.

**The failure modes, stated plainly.** Compromise Codeberg alone and installs get a wrong
key, so verification fails and nothing installs — denial of service, not a bad binary.
Compromise the release host alone and the signature does not match. An attacker needs both,
across two organisations. `PUBKEY_FILE` is the documented way past a Codeberg outage, and
it is the only way past, on purpose.

When the handwritten core reaches Codeberg, the key is already there and the property holds
unchanged — but that is a coincidence, and should not be mistaken for the reason.

## What it costs

- **Time**, and it is the honest objection. The Go is several thousand lines of production
  code plus its tests. Written test-first, which is the chosen method, it is a sustained
  project rather than a weekend.
- **The console is not rewritten**, and its provenance is unchanged. It lives where the
  clause does not govern rather than being cleaned up. That is a deliberate deferral, not a
  claim that the Rails half is fine — see below.
- **Two hosts to keep in step** once the core moves.

## Roads not taken

- **Ignore the rule.** Rejected on taste before anything else. The clause is clear, the
  vote was decisive, and the project's own subject matter is accountability.
- **Argue "mostly."** ~37% generated is defensible arithmetic and an indefensible posture.
- **Move everything to a hosted forge that permits it.** [Tangled](https://tangled.org/) is
  the best of these — no such clause, atproto identity is portable rather than the
  platform's, and self-hostable "knots" for the git storage. Rejected for now because it is
  VC-funded, which is precisely the capture risk this project exists to argue against;
  terms follow funding. GitHub solves the rule and contradicts the thesis, which is why it
  holds the source and nothing an install depends on.
- **Serve the key from a self-hosted forge.** The origins would be independent of the
  release host, but one DNS zone and one Cloudflare account would govern both — a shared
  provider by the rule above.
- **Serve the key from GitHub, beside the source.** One account could then change both what
  a release is built from and the key that vouches for it, and a stale mirror or an expired
  token would sit on the verification path.
- **Keep the code on Codeberg and host the *test suite* elsewhere**, on the reasoning that
  tests are tooling rather than the code itself. Rejected on two counts. Technically it
  cannot work: the test files are internal (`package core` / `package app` / `package
  main`) and test unexported identifiers — `renderRoutes`, `validateTable`, `pickPort`,
  `usedPorts` — so Go requires them beside the source, and moving them means converting to
  black-box tests and losing the cheapest, sharpest coverage we have. And in principle, the
  core's claim is that it is small enough for one person to audit; the test suite is the
  proof of that claim, and a trust core published without it is a worse artifact than the
  one the rule objected to.
- **Rewrite the Rails console too.** Several thousand lines of production code plus tests
  and CSS, most of it views. It buys the same copyright improvement, at triple the cost, on
  the half nobody has to trust. Deferred, not refused.

## Still open

- **The console's own provenance.** Hosting it where the clause does not apply resolves the
  rule and not the licensing question underneath it: an AGPL over largely machine-written
  Rails is as thin as it was. Whether that matters depends on whether anyone is ever
  expected to comply with it.
- **Where the release tooling lives** once `vilice/` is a separate repo — `Makefile`,
  `release/`, and the signing flow currently assume one tree.
- **The first hand-written verb as a trial.** `vilice route` is the candidate: ~200 lines,
  a written spec section, an existing test suite to hold to. An evening spent there says
  more about whether this plan is real than any further argument.
