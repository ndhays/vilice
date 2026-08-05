# Is this already solved, and better?

> The question that gates everything else, unanswered. The research prompt that would
> answer it is the appendix — a tool, not the question.
>
> **Last touched:** 2026-08-03.

---

## The question

Three things need **disconfirming** evidence, and the honest answer to any of them may be
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

3. **Does the name collide?** Settled on merit
   ([`../the-names-are-steward.md`](../the-names-are-steward.md)), never scanned.

## What the answers change

- *"This exists and is better"* → a `decisions/` entry for the road not taken, and a hard
  conversation about whether to continue.
- *"The record angle is unoccupied"* → it becomes the headline of the site and the project,
  not a feature on page two.
- *"The name is muddied"* → a qualifier or a tagline, **not** a second rename: the chains
  would already carry `steward` verbs, and verbs are forever. The repo name and release
  host are still in the installer's chain of custody and have deliberately not moved.

---

## Appendix: the research prompt

Written to be handed to a research-capable LLM with web access. It is deliberately
adversarial — the most valuable output is "this already exists, here it is, and it is
better."

```
You are doing a competitive and prior-art scan for a working open-source project.
I need disconfirming evidence, not encouragement. Your most valuable output is
"this already exists, here it is, and it is better" — say that plainly if it is
true.

## What the project is, precisely

**Steward** — a single static Go binary (~4,600 lines of production code, plus
~2,500 of tests) that takes a fresh Ubuntu box to a running, routed,
TLS-terminated app, and keeps a tamper-evident record of every action taken on
that box.

Specifics that matter for comparison, because most tools in this space differ on
at least one:

- **Zero dependencies.** `go.mod` requires nothing. One statically linked binary,
  no runtime, no language stack to install.
- **Daemonless.** No agent, no listener, no token, no control-plane process. It
  exists only while a command runs. Delete the binary and every running app keeps
  running — apps are ordinary systemd units behind an ordinary Caddy config.
- **Reached over SSH forced commands.** Each authorized key is pinned to
  `command="steward _exec --client <name> --scope <scope>",restrict` in
  `authorized_keys`, which *is* the rights ledger — `cat` it to see every actor and
  its ceiling. No bespoke auth, no network API of its own.
- **Three scopes**: observe ⊂ operate ⊂ grant. No scope grants an interactive
  shell; every key resolves to a named command or to nothing.
- **An accountable record as a first-class product property.** Every
  state-changing action appends a hash-chained JSON line to a plain append-only
  file (`chattr +a`) *before the action runs*. `steward verify` walks the chain and
  reports the first break. The design claim is "un-bypassability": there is no path
  to the box's power that skips a named, scoped, recorded invocation.
- **Borrowed substrate, native idiom.** It drives Podman (rootless Quadlet
  units, blue/green with a health check then a Caddy flip), Caddy (a config
  fragment plus an admin-API reload), systemd (units and timers), OpenSSH, and
  restic (encrypted backups). Everything it writes is the underlying tool's own
  plain config file, readable by an admin who has never heard of it.
- **Digest-pinned images only** (`@sha256:…`); tags are refused.
- **Signed releases** (ed25519) where the installer fetches the public key from a
  *different host* than the binary.
- **Scope**: one box. Not a cluster, not a scheduler, not multi-node
  orchestration, no marketplace.
- A companion web UI (**Steward Console**, a Rails app) exists in-repo but does
  not ship yet. Treat it as a plan, not a product.

Honest weaknesses: Ubuntu-targeted, linux/amd64 only, single-box, and it is not
"hands off" — it greases the path from fresh box to deployed app but does not
manage a fleet on its own.

## What I already know about — do not spend output explaining these to me

Coolify, CapRover, Dokku, Kamal, Dokploy, Portainer, Easypanel, Cosmos Cloud,
Runtipi, CasaOS, Umbrel, YunoHost, Cloudron, Piku, k3s/k0s, Nomad, Ansible,
Terraform, and managed PaaS (Fly.io, Render, Railway). I know the general shape of
the self-hosting PaaS category. Only mention these where you are drawing a sharp,
specific contrast with something above.

Also **Cockpit** and **Flathub**, which are the two nearest neighbours and are worth
naming separately because each is adjacent to a *different* layer:

- **Cockpit** — the machine view's neighbour. Red Hat's per-box web console. It arrives at
  the same statelessness we do (no database; live status read through systemd APIs), and
  differs on all three things that matter: it is a privileged web app **on** every box, it
  hands out a **terminal**, and it keeps **no record of its own actions** — its only audit
  surface is reading the system's SELinux log. **Its multi-machine host switcher is
  deprecated as of Cockpit 322**, which is the single most useful fact about it: the closest
  prior art tried the fleet dimension and retreated to one box at a time. Cuts both ways —
  support for "a fleet is N rows, because the box never knows it is in one", and a warning
  that a well-resourced team found the fleet surface not worth maintaining.
- **Flathub** — the App Library's neighbour, and prior art for the part of the model that is
  still open ([`app-library.md`](app-library.md)): a curated catalog, a declarative
  per-app manifest, a publishing pipeline, and a story for how a third party ships
  definitions someone else installs. Worth mining for manifest shape and curation policy,
  **not** for its build/sandbox model, which solves a desktop problem we do not have.

## Questions, in priority order

1. **The name — collision only.** The name is **settled** on merit
   ([`../the-names-are-steward.md`](../the-names-are-steward.md)); what is *not*
   settled is whether it collides. "Steward" is a common English word with plenty
   of software precedent, which is the trade we accepted for plainness. So: is
   anyone shipping infrastructure or ops software called **Steward**? Look for
   Kubernetes/service-catalog components, config-management tools, agent
   frameworks, and anything with a `steward` CLI on a package index (Homebrew,
   apt, crates.io, npm, Go module proxy). Is the name muddied to the point that a
   search for "steward deploy" or "steward audit log" never reaches us? (I own
   `agoraforge.org`, so a subdomain is always available; this is about collision
   and findability, not availability.) The retired name was "Hostler" — no need to
   research it.

2. **Closest prior art.** Who else ships a *single dependency-free binary* that is
   *agentless and daemonless* and drives an existing box over SSH to deploy
   containers? I care much more about this exact shape than about the PaaS category
   generally. Include small and obscure projects; include Rust and Zig, not just Go.

3. **The record.** This is the part I believe is unusual. Who treats a
   **tamper-evident, hash-chained, written-before-the-act audit record** as a
   product property rather than a log file? Look in three places, not one:
   - self-hosting and deploy tools;
   - access and session management (Teleport, Boundary, StrongDM, Tailscale SSH) —
     note that these mostly record *sessions*, which is a different claim from
     recording *authorized actions before they run*; how different, really?
   - supply-chain and provenance (sigstore, in-toto, SLSA, Rekor's transparency
     log) — is the transparency-log idea already the standard answer here, and does
     that make an on-box chain redundant or complementary?

4. **Alive or dead.** For every project you name: last commit date, release
   cadence, maintainer count, and whether it is one person. I want to know which of
   these are real and which are abandoned demos.

5. **Should I be contributing instead of building?** Given the above, name the two
   or three projects where this work would land better as a contribution than as a
   separate tool — and say concretely what the contribution would be. If the honest
   answer is "none, they are architecturally incompatible," say that and explain why.

6. **Trends, specifically.** Not a general AI essay. I want:
   - Is the self-hosting / "leave the cloud" trend growing or plateauing, with
     evidence (stars, downloads, funding, HN/Reddit volume over time)?
   - Is there a real emerging need for **auditable execution surfaces for AI
     agents** — i.e. agents that act on infrastructure needing a scoped, recorded
     door rather than an unrestricted shell? If so, who is already building it?
     This is the one trend where I suspect my design might matter more than I
     intended it to.
   - What has AI actually changed about the economics of a small open-source infra
     tool: is the bar higher because building is cheap, or is distribution now the
     only thing that matters?

7. **Is there a business here?** Be blunt. Who monetizes in this category, how, and
   at what scale? Distinguish "sustainable one-person project with sponsors" from
   "venture-scale company" from "beloved tool that never made money." Which is
   realistically available to a solo developer starting now?

## How to answer

- **Cite everything** with a link. Distinguish what you verified from what you are
  inferring. If you could not verify something, say "I could not confirm this"
  rather than filling the gap.
- **Dates matter.** Note when you are describing something as of a specific date;
  this space moves.
- Prefer a **table for the landscape** (project · what it is · single binary? ·
  agentless? · audit record? · alive? · link) and prose for the judgement calls.
- Lead with the **three findings most likely to change my mind**, before the
  survey.
- No marketing language, no "in today's fast-paced world," no summary of what I
  just told you.
- If the honest conclusion is "this is a well-built solution to a problem that is
  adequately solved, and the differentiator is too narrow to matter," say exactly
  that. That answer is worth more to me than a list.
```
