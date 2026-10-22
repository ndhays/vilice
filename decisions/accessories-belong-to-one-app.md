# An accessory belongs to one app, and the network is the isolation

> Decided 2026-08-19. Spec: [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md).
> Closes the on-box case of the app-to-app gap named in
> [`provider-boundary.md`](provider-boundary.md), and no other case.

## The decision

**An accessory is a field on one app's spec, and it gets a network of its own.**

```jsonc
"accessories": [
  { "name": "db",
    "image":   "docker.io/library/postgres@sha256:…",
    "volumes": ["web-db:/var/lib/postgresql/data"],
    "env":     { "POSTGRES_DB": "app" },
    "secrets": ["POSTGRES_PASSWORD"] }
]
```

Vilice creates `vilice-<app>`, runs the accessory on it as `<app>-<name>` with the network
alias `<name>`, and joins both of the app's colors to it. The app connects to `db:5432`.
Nothing else joins that network, so declaring a database buys `web → db` and never
`anything → db`.

- **No hostname, never routed.** Caddy does not know it exists.
- **No published port.** Its absence is the isolation; a `PublishPort` here would undo the
  design, which is why the unit-shape fuzz test covers this renderer too.
- **No blue/green.** Two containers over one data directory is not a deploy strategy. The
  accessory is one container that persists across the app's flips.
- **Inside the spec digest.** Changing the database's image is a change to the deploy.
- **Its secrets ride the one envelope**, namespaced in the store by container, so the
  app's `POSTGRES_PASSWORD` and the database's cannot collide.

## Why connectivity and isolation are one decision

The nearest mechanism is the host loopback: publish Postgres on `127.0.0.1:5432`. That
lets every other container on the box dial it too. Build connectivity that way and
isolation cannot be added later without removing the feature.

## Why not "an accessory is just another app"

`validateState` requires a hostname and `waitHealthy` probes HTTP, so an unrouted,
non-HTTP app fails at two gates. Making it work means *app* meaning two things — routed
and not — through validation, health, Caddy and the console's install flow. A scoped,
subordinate noun is smaller: an app is a thing the world reaches; an accessory is a thing
one app reaches.

## What it costs

- **An accessory cannot be shared between two apps.** Two apps sharing a database deserve
  a real database on its own box, or a managed one.
- **Its upgrades ride the app's deploy.** One digest describes the whole thing.
- **A changed accessory restarts** while the app is up. A byte-identical unit is left
  alone, so this happens only when something changed.

## Roads not taken

- **The shared host loopback.** Above.
- **One shared network for all apps on the box.** Same defect — `web` could reach
  `other-app-db`.
- **A separate `Accessory` primitive with its own lifecycle.** More capable and much
  larger: its own record verbs, status, console surface, and a dependency graph. If
  accessories ever need sharing, reach for this deliberately rather than widening the
  field.
- **Removing an accessory's volume when it is undeclared.** Refused. Withdrawing a
  statement of desire is not a destructive act
  ([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)).

## Still open

App-to-app traffic in general — two apps talking, a shared cache, an accessory on its own
box. That goes to the private-network path in [`provider-boundary.md`](provider-boundary.md).
