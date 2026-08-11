---
title: Steward
nav: home
---
<div class="hero">
<h1>Steward</h1>
<p class="tagline">A Tool to Help You Host Your Application(s)</p>
</div>

## Yet Another Hosting Tool?

Steward was built with the goal of making web application hosting boring and durable.
Despite its name, it is not meant to be fancy, but rather safe and predictable. Steward is
also free and open source. While built with purpose, it was built primarily with Anthropic
Claude LLM vibes — so use it at your own risk. Report concerns and submit contributions to
help improve it.

<div class="split">
<div class="split-figure">
<img src="/assets/logo.svg" alt="" width="120" height="120">
</div>
<div class="split-do">

**Install Steward:**

```bash
curl -fsSL https://steward.agoraforge.org/install.sh | sudo bash -s -- 0.3.0
```

[View all Steward commands here](/commands/).

</div>
</div>

Part of Steward's reliability is its controlled access plane: every command is gated by a
scoped SSH key, and every action that changes the box is written to a hash-chained log on
the machine — *before* it is executed, so nothing happens off the books. Security starts by
locking down a fresh Ubuntu box with standard commands and tooling, and then preparing that
machine for its purpose as an app host or a load balancer.

Steward writes almost none of this itself. It is a gate and a scribe, and the work is done
by open source tools that already do it well:

<div class="tools">

- [**OpenSSH**](https://www.openssh.com) — the access plane. The key is the identity and the forced command is its scope. No key gets a shell.
- [**systemd**](https://systemd.io) — residency. Apps are ordinary units and a timer keeps the record ticking, so Steward needs no daemon of its own.
- [**Podman**](https://podman.io) — rootless containers, run as Quadlet units under systemd.
- [**Caddy**](https://caddyserver.com) — hostname routing and automatic HTTPS.
- [**restic**](https://restic.net) — encrypted, deduplicated backups to a repo you own.
- [**UFW**](https://help.ubuntu.com/community/UFW) — the firewall: deny inbound, and open only what the box's role serves.
- [**fail2ban**](https://www.fail2ban.org) — bans repeated SSH authentication failures.
- [**unattended-upgrades**](https://wiki.debian.org/UnattendedUpgrades) — automatic security patching, on a schedule you can see.

</div>

Everything they write is their own plain config file, readable by an admin who has never
heard of Steward — and left in place if Steward is removed.

### Inspiration and Other Self-Hosting Tools

Kamal (and [Once](https://once.com)) were the inspiration that led to the creation of
Steward. The reliability of Linux, the ever-worsening-doom-loop of big name tech, cloud
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

The current version of Steward is a proof of concept. The goal is one day to rebuild it by
hand and host it on [Codeberg](https://codeberg.org), in a way that complies with the
generative-AI clause of their
[Terms of Use](https://codeberg.org/Codeberg/org/commit/96fac426a32d1ba91ff879366d59bf1af54080c2).
Until then the repository is
[self-hosted](https://git.agoraforge.org/agoraforge/steward) on
[Forgejo](https://forgejo.org) — the same software Codeberg runs, and built by the same
people — and deployed with Steward itself.

</aside>
