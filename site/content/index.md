---
title: Vilice
nav: home
---
<div class="hero">
<h1>Vilice</h1>
<p class="tagline">To Help You Host Your Own Applications</p>
<p class="motto"><a href="/horace.html"><span lang="la">Vilice silvarum et mihi me reddentis agelli</span> — Horace, <cite>Epistles</cite> 1.14</a></p>
</div>

## Yet Another Hosting Tool?

Vilice was built with the goal of making web application hosting boring and durable.
Despite its name, it is not meant to be fancy, but rather safe and predictable. Vilice is
also free and open source. While built with purpose, it was built primarily with Anthropic
Claude LLM vibes — so use it at your own risk. Report concerns and submit contributions to
help improve it.

<div class="split">
<div class="split-figure">
<img src="/assets/logo.svg" alt="" width="120" height="120">
<p class="version"><span>Current version</span><strong>v{{version}}</strong></p>
</div>
<div class="split-do">

**Install Vilice:**

```bash
curl -fsSL https://get.vilice.org/install.sh | sudo bash -s -- {{version}}
```

[View all Vilice commands here](/commands/).

</div>
</div>

Part of Vilice's reliability is its controlled access plane: every command is gated by a
scoped SSH key, and every action that changes the box is written to a hash-chained log on
the machine — *before* it is executed, so nothing happens off the books. Security starts by
locking down a fresh Ubuntu box with standard commands and tooling, and then preparing that
machine for its purpose as an app host or a load balancer.

That holds because **no key gets a shell**. Vilice is the accountable control plane, not
your admin access — you still reach the box as yourself, and it sits alongside the tools
you already use rather than replacing them. See
[Not Your Admin Access](/overview.html#not-your-admin-access).

### Dependencies

<p class="tagline">Tools Vilice Builds On</p>

Vilice writes almost none of this itself. It is a gate and a scribe, and the work is done
by open source tools that already do it well:

<div class="tools">

- [**OpenSSH**](https://www.openssh.com) — the access plane. The key is the identity and the forced command is its scope. No key gets a shell.
- [**systemd**](https://systemd.io) — residency. Apps are ordinary units and a timer keeps the record ticking, so Vilice needs no daemon of its own.
- [**Podman**](https://podman.io) — rootless containers, run as Quadlet units under systemd.
- [**Caddy**](https://caddyserver.com) — hostname routing and automatic HTTPS.
- [**restic**](https://restic.net) — encrypted, deduplicated backups to a repo you own.
- [**UFW**](https://help.ubuntu.com/community/UFW) — the firewall: deny inbound, and open only what the box's role serves.
- [**fail2ban**](https://www.fail2ban.org) — bans repeated SSH authentication failures.
- [**unattended-upgrades**](https://wiki.debian.org/UnattendedUpgrades) — automatic security patching, on a schedule you can see.

</div>

Everything they write is their own plain config file, readable by an admin who has never
heard of Vilice — and left in place if Vilice is removed.

### Inspiration

<p class="tagline">Other Self-Hosting Tools</p>

Kamal (and [Once](https://once.com)) were the inspiration that led to the creation of
Vilice. The reliability of Linux, the ever-worsening-doom-loop of big name tech, cloud
price-gauging, and new tools that made deployment within reach to the average developer,
all combined to make the actual computer seem a lot less scary. However, there are a lot of
other great self-hosting tools out there that may be better for your specific needs.

<div class="tools">

- [**Kamal**](https://kamal-deploy.org) — zero-downtime deploys of web apps anywhere, over Docker: rolling restarts, remote builds, and accessory services.
- [**Dokku**](https://dokku.com) — an open-source PaaS alternative to Heroku, and the smallest such implementation around.
- [**Coolify**](https://coolify.io) — self-hosting with superpowers: an open-source alternative to Vercel, Heroku, Netlify and Railway, with hundreds of one-click services.
- [**CapRover**](https://caprover.com) — a scalable, free, self-hosted PaaS that keeps your infrastructure fully under your control.
- [**Cloudron**](https://www.cloudron.io) — a complete solution for running apps on your own server; self-hosting made simpler.
- [**YunoHost**](https://yunohost.org) — a system that installs itself on a server so you can run and maintain your own digital services with very little technical knowledge.

</div>

<aside class="card provisional">

### Proof of Concept

The current version of Vilice is a proof of concept, built with significant use of LLM
tools. The goal is one day to rebuild it by
hand and host it on [Codeberg](https://codeberg.org), in a way that complies with the
generative-AI clause of their
[Terms of Use](https://codeberg.org/Codeberg/org/commit/96fac426a32d1ba91ff879366d59bf1af54080c2).
Until then the repository is on [GitHub](https://github.com/ndhays/vilice). Only the release
key lives on Codeberg, so the key that vouches for a release never comes from the same place
as the release itself.

</aside>
