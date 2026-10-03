# Roles, not packs — a box says what it is for

> Decided 2026-08-06. Narrows what Vilice claims to be, drops the pack layer, and replaces
> it with a role a box declares at `prepare`. The pack design it replaces split the binary
> into a small trust core — the gate, the record, the ceiling — and verb packs dispatched
> through a root-owned manifest. What that design got right — the internal seam and the
> binary integrity check — is kept and named below.

## The question

Two questions turned out to be one.

**What is Vilice for?** The verb list had drifted into implying general Linux
administration — `harden` in particular reads like a security product, and an experienced
admin's first reaction to it is "harden against what?" But of 25 verbs, four touch the OS
and fifteen are app deployment and lifecycle. The tool was describing itself as something
broader than it is, and paying for the difference.

**Where does the pack boundary go?** The pack design split the binary into a trust core
and verb packs so a skeptical reader could audit the core rather than the whole thing. It
deferred the physical split until a real second pack existed. None ever appeared.

## The decision

**Vilice hosts web applications on a Linux server.** Not general administration. Cockpit
does that, does it well, and Vilice should point at it rather than compete
([`open/landscape-scan.md`](open/landscape-scan.md)).

**Packs are dropped.** One binary, all verbs, no plugin layer.

**A box declares a role instead** — `vilice prepare host` or `vilice prepare balancer` —
and what gets installed and which ports open follow from it. See
[`../blueprint/vilice/provision.md`](../blueprint/vilice/provision.md).

## Why packs go: two arguments that arrive together

**The seam has nothing on the far side, permanently.** `vilice-backup` and `vilice-diag`
were the hypothetical second and third packs. But once the product is "host web apps,"
backup and diagnostics *are* the product, not extensions to it. The pack design's own
rule — *"a real second use case triggers it, not symmetry"* — now cuts against the thing it
created. A boundary that will never be crossed is scaffolding.

**And the handwritten rewrite substitutes for it.** This is the argument that decides it.
The pack split existed to bound what a skeptical reader must trust: audit the core, not the
whole binary. Handwriting-with-validation
([`the-core-is-handwritten.md`](the-core-is-handwritten.md)) bounds it a different way — by
making the whole thing understood by the person who wrote it. **Two mechanisms for one goal
is one too many.** 5,700 lines written and validated line by line is a credible "audit the
whole binary" claim in a way 5,700 machine-written lines never was.

Neither argument alone would be enough. Together they are.

## What is kept, and what goes

**Kept — and it earns its keep.** `SelfDigest` is the sha256 of the running binary; `prepare`
records it; every verb checks the running binary against that record before it runs. If
someone swaps `/usr/local/bin/vilice`, the verb refuses and the refusal is recorded. That
is real tamper detection on the hot path, and it survives with a plainer name: the file
records **one binary digest**, not a list of pack authorizations.

Note the deliberate asymmetry worth preserving: `verify`, `record`, `actors`, `authorize`
and `revoke` still work when the digest record is missing or mismatched, so an operator can inspect and repair
a box whose binary was replaced rather than being locked out by the integrity check itself.

**Kept — free, and worth having.** The internal code seam. `internal/core/` and the verb
implementations stay separate files with a documented line between them. That is
organisation and documentation, not a plugin system; nothing loads anything. Drawing the
line showed the three places the core knows about apps, and they are where to look first
when the seam blurs: **`prepare`**, which installs the app layer's substrate; **`status` /
`doctor`**, which report container and route state; and **`uninstall`**, which needs the
app list to plan, and the backup settings to warn the operator before a restic password
is lost. `uninstall` removes apps by running Vilice's own `remove` as a subprocess rather
than reaching into deploy internals — the command surface was already the boundary there.

**Gone.** The discovery directory `/usr/libexec/vilice/`, which was reserved and always
empty. The `$PATH`-is-attack-surface reasoning, which was correct and is now moot. The
`execveat`/`AT_EMPTY_PATH` TOCTOU closure, which was always **prose rather than code**
because there was never a separate file to race against. The "directory locates, manifest
authorizes" distinction, which with one compiled binary was doing no work.

## Roles are a closed set, and the shortness is the finding

The test that decides what earns a role:

> **If it can run in a container, it is an app, not a role.**

A role has to be something a container cannot be: it owns the machine's network position,
needs privileged or kernel-level setup, or requires substrate no app host needs.

That kills almost everything. A registry, a database, a monitoring stack, a CI runner, the
Console itself — all of these are apps with volumes. What survives and is in scope:

| Role | Why it is one |
|---|---|
| `host` | runs containers: Podman, uidmap, restic, Caddy |
| `balancer` | owns :80/:443 and therefore cannot sit behind itself; Caddy alone |

`vpn` passes the test and is out of scope for now
([`the-vpn-is-not-a-control-path.md`](the-vpn-is-not-a-control-path.md)). `mail`, `dns` and
`storage` pass it and are different products.

**The list being short is the point.** The exercise was run looking for a long one, and
there isn't one — which is the strongest evidence that roles are a closed set rather than a
taxonomy wanting a plugin system. The same conclusion the pack question reached, arrived at
from the opposite direction.

So a third role waits for a third real case, exactly as the second pack was supposed to.
The difference is that this time the machinery costs nothing while we wait: a role is a
word in a file and a switch statement.

## What the role buys

- **Substrate follows purpose.** A balancer no longer installs Podman and restic to never
  use them — surface to patch for no benefit.
- **`deploy` refuses by name** on a balancer, instead of the operator meeting
  `podman: not found` and guessing.
- **The machine view shapes itself around the role**, which is what the pack-shaped view was
  for. The console asks the box what it can do, and the box answers from what it *is* rather
  than from a registry of plugins. The property is kept; the machinery is not.
- **It is recorded.** `prepare-role` in the chain, so "what is this machine for, who said
  so, when" is answerable from the record rather than inferred from what happens to be
  installed.

## Ports move to the role; `harden` closes and nothing more

Hardening opened 80/443 as part of a fixed baseline. But whether a box serves web is a fact
about its **role**, not about its lockdown — so `harden` now opens sshd's port and nothing
else, and `prepare <role>` opens what the role serves.

Two constraints hold this together:

- **The port allowed is the one sshd is actually configured for**, never the constant 22. A
  rule that assumes 22 locks you out of a box reached on 2222, and a remote lockout has no
  repair. (The code already read `$SSH_PORT`; the rule is now written down.)
- **`prepare` never installs or enables a firewall.** `harden` is optional and `prepare` is
  required, so a dependency here would quietly make hardening mandatory and break *"a box is
  accountable even un-hardened."* No firewall means nothing to open, and that is fine.

## `harden` keeps its name

Considered and rejected: `lockdown` and `baseline`.

The objection to `harden` is real — it is jargon, it is vague about *what*, and it fails this
project's own naming rule that a name should say what the thing is. `lockdown` was rejected
as **lateral**: it swaps one metaphor for another, carries heavy non-technical connotation,
and mis-implies reversibility (a lockdown ends; this is permanent config). `baseline` was the
best alternative and still not clearly better.

**A lateral rename costs chain-record continuity and buys nothing**, and `harden` has real
discovery value — people search for how to harden a server. Kept.

What fixes the underlying problem is not the name but the **frame**: once Vilice is
explicitly about hosting web apps, `harden` stops sounding like a competing security product
and reads as what it is — get the box into a sane state before it serves anything. And the
answer to the skeptical admin was always `harden --check`, which reads `sshd -T` and `ufw`
authoritatively and reports drift. Hardening is a posture that decays, this agrees, and
almost nothing else in the category can prove its own claim slipped.

## `status` always includes security

Previously the section was omitted entirely when no posture had been published, so a box
that was never hardened looked like a box with nothing to report. **Absence is a fact here**,
the same way an unreachable box reports *unknown* rather than *none*. An optional security
view is an ignorable one, and the default answer to "how is my box" must not silently drop
whether it is exposed.

## What it costs

- **"What must I trust?" becomes "the binary" rather than "the core."** Acceptable *only*
  because of the handwritten rewrite. Dropping packs while keeping generated code would be
  losing something for nothing.
- **A third role is now a code change** rather than a plugin. Correct at two roles; it would
  be wrong at ten, and ten is not coming.
- **The console loses `PackState`** and the pack-shaped machine view, replaced by the role.
  Simpler, and the pack-shaping was solving a problem packs created.

## Roads not taken

- **Keep packs, ship separate binaries.** The compelling case finally appeared — a balancer
  needs Caddy and nothing else, so substrate genuinely diverges. But that argues for
  *conditional substrate*, not two binaries. Separate binaries buy independent release
  cadence and per-pack digest pinning; a solo project with one pipeline values neither, and
  the audit surface is already covered by the rewrite.
- **Packs as per-app features** (`pack-accessory`, `pack-backup`) — an app declares what it
  needs and the box must have it. That is a **dependency**, and `AppConfig` already expresses
  it. Routing it through a pack adds indirection over something the spec says directly. The
  real content of the intuition — that what a box installs should follow from what it is
  asked to run — is the same conditional-substrate mechanism, arriving from the app side.
- **Merge `harden` into `prepare`.** Tempting: it deletes the word that causes trouble. But
  `provision.md` makes them *optional* and *required* respectively, and merging forces
  either mandatory hardening (wrong for a box behind a cloud firewall or its own CIS
  baseline) or optional accountability (definitely wrong). The good idea inside it — that
  firewall policy should follow the role — was taken without the merge.
- **A `worker` role** (runs jobs, serves no HTTP). Identical substrate to `host`, different
  ports. That is a host with a port profile, not a role — and it is the evidence that role
  and firewall are separate axes, which is why ports are chosen *by* role rather than baked
  into it.
