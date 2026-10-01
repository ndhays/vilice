# Security audit — how the posture is measured

The claim "Steward hardens the box and keeps an honest record" has to be *measured*, not
asserted. This is how, and why it's shaped the way it is. Settles the "Security
smoke-tests" thread in `decisions/open/vilice-open-questions.md`.

## Three audits, different homes

Security tooling splits into kinds that don't belong together:

- **Code audit** — `govulncheck` + `gosec` over the Go source. Deterministic, no box
  involved. Lives in `make audit`.
- **Box-posture audit** — `ssh-audit` + `nmap` + `Lynis` against a prepared+hardened
  box. Closes the loop on `harden/` — proves the bash did what it claims. Needs a live
  box; lives in `make audit-box HOST=…`.
- **Gate audit** — the adversarial tests over Steward's own boundary: `gate_test.go`
  (who may reach what) and `inject_test.go` (what a value may become once rendered).
  Ordinary `go test`, plus `make fuzz` to run the fuzz targets past their seed corpus.

Keeping them apart matters: different cadence, different "fail" meaning, different owner.

### Why the third leg exists

The first two measure the **toolchain** and the **box**. Neither measures the **gate** —
and for a program whose entire claim is un-bypassability, that was the gap that mattered.
The 2026-08-01 audit found six live findings in a well-tested package precisely there:
nothing had ever handed Steward a hostile string and checked what it did.

The tests are written as **properties over the commands table**, not as cases. "Every
command whose synopsis takes an `<app>` refuses a traversal name" covers the command
added next month; "every value validation admits renders into exactly the directives the
renderer emits" covers the config field added next month. The failure mode being
defended against is not a missing check — it is a check written once and forgotten in
the five places that also needed it, which is how every finding in that audit began.

The fuzz targets are the part that finds what nobody listed. Within a minute of first
running, `FuzzCaddyfileShape` refuted a block-list that had looked complete: a hostname
of `#` comments out its own site block and breaks routing for every app on the box. Its
failing input is checked into `testdata/fuzz/`, so it is a permanent regression test —
which is the shape all of these should take.

## `make audit` gates `release`, not `build`

Build runs constantly in the dev loop; it stays fast and offline. The audit needs the
network (vuln DB) and is slower, so it hangs off `release` instead (`release: audit
sign`). Release is rare and deliberate — the right moment for "this version was
measured." That gate *is* the teeth; **CI stays manual** on purpose (the process is
deliberately slow). A govulncheck finding usually means the **build toolchain is behind**
— the remediation is to bump Go to the latest patch release, not to touch the code.

## gosec policy: G204 stays on, the perms/path rules don't

Steward's whole job is to shell out (ssh / podman / systemctl / caddy) and to write
system files at deliberate permissions. So gosec's defense-in-depth rules —
**G301/G302/G304/G306** (dir/file perms, path-from-variable) — fire on choices that are
correct by design: the record is **world-readable on purpose** (observe is
zero-privilege, and the record ships off-host), systemd units are conventionally `0644`,
Caddy's root service reads the fragment, and every "tainted" path is steward's *own*
configured path, never user input. Those four are excluded by policy (documented in
`steward/Makefile`). The security-critical **subprocess rule G204 stays on** and is
annotated per call site with the reason each input is trusted — the annotation is the
audit.

**The pins move with the toolchain, and a bump is an audit of its own.** Go 1.27 broke
gosec v2.22.9 (its `x/tools` could not load the new standard library), so the pin went to
v2.29.0 on 2026-09-29 — and the newer analysis reached three exec helpers that had never
been annotated: `core.Sh`, `core.CmdFirstLine`, `app.userExec`. Writing the annotations is
what found the real gap. Two of the three are trivially safe (their arguments are this
binary's own literals). The third takes app names, and `ValidAppName` allowed a **leading
dash** — so an app called `-H` would have been handed to `systemctl` as a flag: argv
injection with no shell in it. The name rule now requires an alphanumeric first character,
the hostile-name corpus carries the argv shapes, and the console's `NAME_FORMAT` moved with
it. The lesson is the one the third leg exists for: the finding came from having to state
the claim out loud.

## The on-box check: native, not the scanners

`ssh-audit` is the obvious tool to "bake in" — and the wrong one to. It's a large Python
tool wrapped around a continuously-updated cipher/KEX policy database. Reimplementing it
in Go means chasing that policy forever; shelling out to it adds a **runtime dependency
Steward doesn't control** and breaks the **single static zero-dep binary** property that
the whole install story rests on. So the scanners stay external (`make audit-box`), the
periodic deep audit you fold back into `harden/`.

What *is* in-grain is a **native, dependency-free self-check** of Steward's own hardening
contract: `harden --check`, running the generic `harden/check.sh` probe. It's the piece
that runs forever (the everyday guard), not just at audit time.

## The privilege split: root writes the fact, observe reads it

`harden --check` needs **root** (authoritative `sshd -T` / `ufw`). Steward Console's observe
path is the **unprivileged `steward` user**. They don't compose — and we do **not**
escalate observe to bridge them. Instead the project's own CQRS pattern applies: the
privileged side **publishes a fact** (`/var/lib/steward/hardening.json`, root-written,
`0644`), and observe **reads** it via `status`. The reader never reaches into root state;
root state is written down for it. "A stamp can rot" is answered not by a live read
(impossible at observe privilege) but by **re-publishing on every check**, so the fact
carries its own `checked_at` and staleness is visible.

This also keeps `harden --check` off the **audit chain**: it's a read (like `verify`), it
must work before `prepare` lays the floor, and the fact it emits belongs in the **status
lane**, not the hash-chained action record. See `dispatch`'s `recordable()` and
[blueprint/vilice/record.md](../blueprint/vilice/record.md).

And it stays out of `doctor`: `doctor` answers "ready to deploy?" as the unprivileged
steward user; hardening is optional and needs root. Folding it in would break both
optionality and the privilege boundary, so `doctor` only prints a pointer to
`harden --check`.

## Roads not taken

- **OpenSCAP** — enterprise compliance machinery (CIS/STIG/PCI), Red Hat-centric, weak
  Ubuntu content. Overkill and against the own-it grain; `Lynis` covers the same ground
  lighter. Revisit only if a formal CIS-Ubuntu profile is ever required.
- **Trivy / testssl.sh** — deferred, not rejected. Trivy belongs scanning the Steward Console
  image (no image for the Steward binary); `testssl.sh` needs a real cert and rides with
  the DNS-01 / HTTPS work.
- **A `/etc` "hardened at" timestamp** — rejected. A stored stamp is a claim that drifts
  from reality (re-enable root SSH and the stamp still says "hardened"). The live
  `harden --check` is ground truth; the published fact's `checked_at` is the honest "as
  of" without pretending to be current.
