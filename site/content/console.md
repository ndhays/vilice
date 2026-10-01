---
nav: console
title: Vilice Console
---
# Vilice Console

Vilice Console is a GUI-based approach to Vilice via a Rails app. It can be deployed with
Vilice itself, or run locally. For more details see the console code inside the
[monorepo](https://git.agoraforge.org/agoraforge/steward).

It holds no privilege of its own. Each machine is reached over scoped SSH with its own key,
authorized on the box at `observe` to read or `operate` to deploy — so the console can run
anywhere, and revoking one box never touches another.

## Install

Vilice Console is an ordinary app with an ordinary AppConfig:

```jsonc
// console.json — Vilice Console's own AppConfig
{
  "image":     "ghcr.io/agoraforge/vilice-console@sha256:…",
  "hostnames": ["console.example"],
  "port":      4000,
  "health":    "/up",
  "env":       { "HTTP_PORT": "4000" },
  "secrets":   ["RAILS_MASTER_KEY"],
  "volumes":   ["vilice-console-storage:/rails/storage"]
}
```

See [AppConfig](/overview.html#appconfig) for what each field means. It deploys the ordinary
way, with one addition — the master key.

## The Master Key

`RAILS_MASTER_KEY` is the console's one secret, and it earns the name: it unlocks the keys
that protect each machine's SSH key at rest. Rails generates it with the app, it lives in
`config/master.key`, and it is deliberately not in the repository.

The config above only *names* it. The value travels the other half of the deploy envelope,
on stdin, so it never reaches the recorded command line and is never written to the record.
Building the envelope in the pipe keeps the key out of a second file — with `jq`, that is
one line:

```bash
jq --arg key "$(cat config/master.key)" \
   '{ app: ., secret_values: { RAILS_MASTER_KEY: $key } }' console.json \
  | vilice deploy console
```

Vilice stores the value in the box's Podman secret store and injects it into the container
as env. It is needed on **every** deploy, not just the first — a deploy that omits it is
refused. A backup never includes the secret store, so this key is yours to keep: restoring
onto a fresh box means supplying it again, or the console comes up unable to read its own
machine keys.

See [Secrets](/overview.html#secrets) for the general rule.

## Boxcar

Vilice Console is built on **[Boxcar](https://boxcar.run)** — a Rails pattern language that
encodes
[Agora Constitution](https://git.agoraforge.org/agoraforge/steward/src/branch/main/blueprint/agora.md)
articles as composable concerns: identity, the accountable record, scoped decisions.
