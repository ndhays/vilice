# Rendered config is a boundary

> Decided 2026-08-01. Every file Steward writes on a caller's behalf — `authorized_keys`,
> the Caddy fragment, a Quadlet unit — is a **trust boundary**, validated with an
> allow-list before it is rendered. Found by a security audit of the whole surface;
> the mechanism is `validateState` / `validHostname` / `looksLikePubkey`, plus the fuzz
> targets in `steward/inject_test.go`.

## The bite

Steward was careful in exactly one direction. Nothing a caller sends reaches a shell:
`SSH_ORIGINAL_COMMAND` is split into named arguments and never interpreted, secrets ride
stdin and never argv, and every host-side `bash -c` interpolates only Steward's own
constants. Command injection — the classic forced-command failure that
[auth.md](../blueprint/vilice/auth.md) names — was genuinely closed.

Config injection was wide open, because nobody had thought of the rendered file as an
input at all. Three formats, all line-oriented, all built by string interpolation:

- **The Caddy fragment.** An `operate` key deploys with a hostname containing a newline
  and writes whole site blocks into the config a root-run Caddy imports.
- **A Quadlet unit.** A volume string containing a newline adds any directive it likes —
  `PodmanArgs=--privileged`, `AddCapability=…`.
- **`authorized_keys`.** A "public key" containing a newline writes a *second* line with
  no forced command and no restrictions: a full shell grant smuggled in as a key comment.

Same bug, three faces. In a line-oriented format, a value that can end its own line can
write the next directive.

## The decision

**A value is validated before it is rendered, and the validation is an allow-list.**

- No control character reaches any rendered file (`hasControlChar`).
- A hostname must *look like a site address* — optional scheme, optional `*.` wildcard,
  letters/digits/dots/hyphens, optional port (`validHostname`).
- A public key must be one line: known type, base64 blob, at most a comment
  (`looksLikePubkey`).
- An app name is `[A-Za-z0-9_-]` and may not begin with a dash (it is handed to
  `podman` and `systemctl` as an argument, where a leading dash reads as a flag —
  argv injection with no shell in it), checked at the door for every command whose synopsis
  says `<app>` — not per command, which is how five lifecycle verbs missed it.

**Allow-list, not block-list.** This is the part worth remembering. The first fix here
*was* a block-list — reject newlines, braces, and whitespace in a hostname — and it
looked complete. The fuzzer refuted it in under a minute with `#`: a hostname of `#`
comments out its own site's opening line, leaving a dangling `reverse_proxy` that makes
the fragment invalid and breaks routing for **every app on the box**, not just that one.
A block-list needs you to have thought of the character. An allow-list only needs you to
know what a hostname is.

## Bind mounts are confined

The same audit found the scope ladder didn't hold: `observe ⊂ operate ⊂ grant` is a claim
about reachability, and an `operate` key could step over it two ways. A volume spec of
`/:/host:rw` passed validation and bind-mounted the host filesystem into a container,
from which `~steward/.ssh/authorized_keys` is writable — and writing that file *is* a
grant. A hostile restic repo reached the same file through `restore --target /`.

So:

- **Bind-mount sources live under a declared root** (`/srv` by default, `STEWARD_BIND_ROOTS`
  to change it). Named volumes are unrestricted — Podman owns that namespace and keeps
  them inside the steward user's own storage. This matched practice already: every
  documented example uses named volumes, and the existing bind-mount test used `/srv`.
- **A restore is confined with `--include`** to the app's declared volumes and its spec
  file. restic puts absolute paths back where they were, and the paths come from the
  snapshot — so an unbounded `--target /` lets whoever controls the repo write anywhere
  the steward user can.

## Where the checks sit — two tiers, on purpose

There are two different kinds of rule here, and conflating them breaks upgrades.

- **Rendering safety** — can this value end its own line and start a directive nobody
  wrote? Control characters, and hostnames that aren't site addresses.
  `validateRenderable`, checked **everywhere**: the doors, `saveApp`, `writeUnit`,
  `refreshCaddy`. It is about the *shape of the file being written*, so it applies just
  as much to state read back off disk.
- **Policy** — is this app allowed to ask for this? Currently just where a bind mount may
  live. `validateState` (= renderable + policy), checked only where a spec **enters** the
  box: a deploy, and a restore.

The first version checked policy at the render boundary too, which looked more thorough
and was wrong. Tighten the bind-mount rule and every box with data at `/data` stops being
able to route *anything* — an app that was already there, already working, and never
attacker-supplied, retroactively condemned by a rule written after it. Checking policy on
the way in is enough for the security property, because exploiting it means *introducing*
a hostile volume, and the two doors are the only ways to do that.

`loadApp` deliberately validates neither: an app whose spec no longer passes should fail
loudly the next time someone deploys it, not vanish from `status` and lose its route.

The upgrade behaviour this buys is pinned by a test — an app with a legacy bind mount
still renders, still persists, still routes, and is refused only when someone tries to
deploy it again.

## Roads not taken

- **Escaping instead of refusing.** Quoting a hostname for Caddy, escaping a newline for
  systemd. Each format has its own escaping rules, `%q` is Go's and not OpenSSH's, and
  every one of them is a place to be subtly wrong forever. Refusing is one rule, and the
  error tells the operator what shape the value should be.
- **Validating only at the CLI door.** Cheaper, and wrong for rendering safety: specs
  also arrive from restic snapshots and from files on disk, and the render boundary is
  the one every path crosses. For *policy*, though, the door is exactly right — see the
  two tiers above.
- **One validation function for everything.** What was shipped first. Simpler to read,
  and it silently made every policy rule retroactive to apps already installed.
- **Dropping bind mounts entirely** (named volumes only). It would remove the class
  rather than bound it, and it is tempting. Rejected because `volumeDirs` supports bind
  mounts on purpose and some apps genuinely want a path they can see from the host —
  confining them to a root gets the same safety without taking the feature away.
- **A block-list of dangerous characters.** See above. It was tried, it passed review,
  and the fuzzer broke it immediately.

## What this answers preemptively

"Can a deploy change anything outside its own app?" — No. Its hostname becomes one Caddy
site, its volumes stay inside the data root, its unit contains only directives Steward
emits, and its name cannot leave the apps directory. If you can't name the check, it
isn't enforced — so each of those is a test in `steward/inject_test.go` or
`steward/gate_test.go`, most of them derived from the commands table so a new command
inherits them.
