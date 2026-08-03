# What Could Go Wrong (common pitfalls)

> A running list of the things that trip people up — so they don't have to send an
> email or open an issue. The goal: **the failure should tell you the fix.** As each
> gets handled (a clearer error, a `doctor` check, a docs note), move it out. This is
> close to a stated value, not just a checklist: software that fails loudly and points
> at the cause.

> **Scope: accidents, not adversaries.** Everything below is the honest operator
> tripping over the box. The other half — what someone *holding a key* could do on
> purpose — is not a running list but a contract, so it lives in the spec and its tests:
> [`rendered-config-is-a-boundary.md`](../rendered-config-is-a-boundary.md) for what a
> value may become once written to a config file, and the "gate audit" leg of
> [`security-audit.md`](../security-audit.md) for how the scope ladder is measured
> (`steward/gate_test.go`, `steward/inject_test.go`, `make fuzz`). Noticing that the
> adversary view had no home is what prompted the 2026-08-01 audit; keeping the two
> apart is deliberate, because a pitfall gets a friendlier error while a boundary gets
> a test.

## Cloud-provider firewall (not just `ufw`)

The biggest gotcha. Hetzner / Vultr / DigitalOcean put their **own** firewall in front
of the box, separate from `ufw`. If Steward Console can't reach the box over SSH, or an
app's 80/443 are unreachable, **check the provider firewall first** — `ufw` can be
perfect and the traffic still blocked upstream. (A Hetzner Cloud Firewall attached to
the server commonly blocks inbound by default.)
→ A future `doctor`/Steward Console check could probe reachability and say so explicitly.

## DNS not pointing yet / ACME fails

Caddy gets HTTPS automatically — but only if the hostname's A/AAAA record points at the
box and 80/443 are reachable. No DNS (or a proxied "orange-cloud" Cloudflare record)
→ ACME can't validate → the site doesn't serve. For boxes without a real domain, use an
`http://` hostname in `deploy --hostname`.

## SSH from Steward Console can't connect

- The provider firewall (above) is blocking 22.
- The key wasn't authorized (`steward authorize …`), or you're connecting as the wrong
  user — scoped keys live in the **`steward`** user's `authorized_keys`, so Steward Console
  connects as `steward@box`, not `root@`.
- `ssh -v` from the Steward Console host usually shows which.

## Locked out after `harden`

`harden` disables password auth. If your only key is wrong or missing, you're out — use
the provider's **web console** (the out-of-band floor). `harden` refuses to disable
passwords when root has no `authorized_keys`, specifically to prevent this.

## Control-plane gotchas (the install flow)

These are Steward Console-side, not box/network — they come with the install journeys
([install-journeys.md](install-journeys.md)). The same value applies: **the failure
should tell you the fix.**

- **The authorize gap.** A newly-added machine is unreachable until the operator runs the
  surfaced `steward authorize …` line on the box. An install aimed at a box that hasn't
  authorized Steward Console's operate key should say exactly that — *"this box hasn't
  authorized Steward Console yet — run this line"* — not throw a cryptic SSH failure. (Check
  reach at the install's `ready` transition.)
- **Provisioning failure** (automated dedicated). A bad/absent provider token, a quota,
  or the cloud firewall above can stall a Create Machine. The install's `awaiting_machine`
  state must be able to surface **"provisioning failed"** and not hang forever.
- **Orphans / resumability.** A multi-step install that dies mid-flow must leave a
  **resumable** row in an honest state, never a zombie — resume or discard, your choice.
- **Version drift, said out loud.** An install pins its `Version` at install time; when
  the App's *latest* moves, existing installs do **not** silently update. Surface it as an
  offer — *"v1.3 is now latest — re-deploy?"* — not a surprise.

## "version mismatch" / install 404

The site's `/releases/` must contain the current `VERSION`. Run
`make -C steward release`, then build + deploy the site. The site build guard catches
this locally; a stale upload (missing `/releases/`) shows up as a 404 from `install.sh`.
