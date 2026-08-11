---
nav: console
title: Steward Console
---
# Steward Console

Steward Console is a GUI-based approach to Steward via a Rails app. It can be deployed with
Steward itself, or run locally. For more details see the console code inside the
[monorepo](https://git.agoraforge.org/agoraforge/steward).

It holds no privilege of its own. Each machine is reached over scoped SSH with its own key,
authorized on the box at `observe` to read or `operate` to deploy — so the console can run
anywhere, and revoking one box never touches another.

## Install

Steward Console is an ordinary app, deployed the ordinary way:

```bash
steward deploy console < console.json
```

```jsonc
// console.json — Steward Console's own AppConfig
{
  "image":     "ghcr.io/agoraforge/steward-console@sha256:…",
  "hostnames": ["console.example"],
  "port":      4000,
  "health":    "/up",
  "env":       { "HTTP_PORT": "4000" },
  "secrets":   ["RAILS_MASTER_KEY"],
  "volumes":   ["steward-console-storage:/rails/storage"]
}
```

`RAILS_MASTER_KEY` is the console's one secret. Steward injects it as container env, out of
the record. It unlocks the keys that protect each machine's SSH key at rest.

See [AppConfig](/overview.html#appconfig) for what each field means.

## Boxcar

Steward Console is built on **[Boxcar](https://boxcar.run)** — a Rails pattern language that
encodes
[Agora Constitution](https://git.agoraforge.org/agoraforge/steward/src/branch/main/blueprint/agora.md)
articles as composable concerns: identity, the accountable record, scoped decisions.
