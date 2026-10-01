# An accessory belongs to one app, and the network is the isolation

> Decided 2026-08-19, building the database-next-to-the-app path. The canonical *what* is
> [`blueprint/vilice/deploy.md`](../blueprint/vilice/deploy.md); this is the *why* and
> the roads not taken. Closes the app-to-app gap
> [`provider-boundary.md`](provider-boundary.md) names — *"app-to-app traffic, which has
> no path at all today"* — for the on-box case, and deliberately not for any other.

## The problem

A Rails app needs Postgres. An app on Steward is one container plus volumes, and nothing
can reach anything else, so the honest answer until now was *use a managed database*. That
is a real answer, and it is not the only one people need.

The trap is that **connectivity and isolation are the same decision here**, and only once.
The single-box mechanism nearest to hand is the shared host loopback: publish Postgres on
`127.0.0.1:5432` and let the app dial it. That works, and in the same stroke it lets *every
other container on the box* dial it too. Build connectivity first and isolation is no
longer available without taking the feature away again.

## What we chose

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

Steward creates `steward-<app>`, runs the accessory on it as `<app>-<name>` with the
network alias `<name>`, and joins **both of the app's colors** to the same network. The
app connects to `db:5432`. Nothing else ever joins that network — so declaring that `web`
needs a database buys `web → db` and never `anything → db`.

Subordinate by construction, and every part of that is deliberate:

- **No hostname, never routed.** Caddy does not know it exists.
- **No published port.** Its absence *is* the isolation; a `PublishPort` here would
  quietly undo the whole design, which is why the unit-shape fuzz test covers this
  renderer too.
- **No blue/green.** An accessory holds data on a disk, and two containers over one data
  directory is not a deploy strategy. It is a single container that persists *across* the
  app's flips while the colors come and go around it — the same rule `replicable?` already
  applies one layer up: a thing that keeps data is single.
- **Inside the spec digest.** Changing the database's image is a change to the deploy, not
  a detail beside it.
- **Its secrets ride the one envelope**, namespaced in the store by container, so the
  app's `POSTGRES_PASSWORD` and the database's cannot collide.

## Why not "an accessory is just another app"

This was the first instinct, and the seed catalog encourages it — `redis` and `postgres`
are already library entries with ports and no health path.

They cannot actually be deployed. `validateState` requires a hostname and `waitHealthy`
probes **HTTP**, so an app that nothing routes to and that does not speak HTTP fails at two
gates. Making them work means teaching *app* to mean two different things — routed and
not — and threading that distinction through validation, health, Caddy, and the console's
whole install flow.

Adding a scoped, subordinate noun is smaller and says something truer. An app is a thing
the world reaches. An accessory is a thing one app reaches.

## What it costs

- **An accessory cannot be shared between two apps.** Under this design that is a feature
  rather than a gap: two apps sharing one database is a coupling that deserves to be a
  real database on its own box, or a managed one. But it is a genuine limit and someone
  will meet it.
- **Its upgrades ride the app's deploy.** Changing the Postgres image is a spec change
  like any other, which means the app redeploys with it. Acceptable, and it keeps one
  digest describing the whole thing.
- **A changed accessory restarts**, briefly, while the app is up. There is no second
  colour to flip to, because there cannot be. An accessory whose unit is byte-identical is
  left alone precisely so this only happens when something really changed.

## Roads not taken

- **The shared host loopback.** The easy one, and the reason for writing this down: it
  grants every container the same reach in the same stroke, and it cannot be narrowed
  afterwards without removing the feature.
- **One shared network for all apps on the box.** Same defect, one layer up — `web` could
  reach `other-app-db`.
- **A separate `Accessory` primitive with its own lifecycle**, deployable and upgradeable
  on its own. More capable and much larger: it needs its own record verbs, its own status,
  its own console surface, and a dependency graph between it and the apps that use it. If
  accessories ever need to be shared, that is the design to reach for — and it should be
  reached for deliberately, not arrived at by widening this one.
- **Removing an accessory's volume when it is undeclared.** Refused. Undeclaring a
  database must not be how its data disappears, which is the same rule the console's
  intention layer follows: withdrawing a statement of desire is not a destructive act
  ([`drift-is-surfaced-never-closed.md`](drift-is-surfaced-never-closed.md)).

## What this does not answer

**App-to-app traffic in general.** An accessory is reachable by exactly one app, on
purpose. Two apps that need to talk to each other, or a shared cache, or an accessory on
its own box, are all still unaddressed — and the private-network path in
[`provider-boundary.md`](provider-boundary.md) is where that goes when it becomes real.
This closes the case that was blocking an ordinary Rails app, and nothing wider.
