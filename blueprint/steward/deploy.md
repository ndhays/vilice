# Steward — Deploy & Lifecycle

Putting an app on the box and running it. This is the **wide, not deep** part: a state
machine whose failures are loud and recoverable. The deep parts are borrowed — Caddy
routes traffic and handles TLS, Podman runs the container. Everything here runs under
`operate` scope ([auth.md](auth.md)) and writes its record first ([record.md](record.md)).

**Status:** Canonical. Last touched 2026-08-19.

---

## `steward deploy <app>` — declarative apply

Deploy is a **declarative upsert**: you hand Steward the app's *full desired state* and
it converges the box to it. There is no separate `apply` and no incremental state to
lean on — **the first deploy and the Nth are the same call**, each self-contained.
Full-replace semantics: an omitted field is *removed*, not left as-is.

The desired state arrives as a **JSON envelope on stdin**, so secret *values* never
touch the recorded command line (argv is recorded; stdin is not):

```jsonc
{
  "app": {                              // recorded by digest (sans values)
    "image":     "…@sha256:…",          // digest-pinned — a tag is never what runs
    "hostnames": ["app.example"],
    "port": 8080, "health": "/up",
    "env":     { "RAILS_ENV": "production" },  // config — recorded
    "secrets": ["RAILS_MASTER_KEY"],           // names only — recorded
    "volumes": ["app-data:/rails/storage"],
    "release": ["bin/rails", "db:migrate"],    // argv — run once before the new color
    "accessories": [                           // reachable by this app and nothing else
      { "name": "db", "image": "…postgres@sha256:…",
        "volumes": ["app-db:/var/lib/postgresql/data"],
        "secrets": ["POSTGRES_PASSWORD"] }
    ],
    "processes": [                             // the same image, a different command
      { "name": "worker", "command": ["bin/jobs"] }
    ]
  },
  "secret_values": { "RAILS_MASTER_KEY": "…" } // bound, never recorded
}
```

A **flag form** is kept for the simple, no-secret path:
`steward deploy <app> --image <ref@sha256> --hostname <host> [--port <port>] [--health <path>]`.

Every field is validated before anything is written. The app **name** is
`[A-Za-z0-9_-]` (it becomes a filename and a systemd unit name), a **hostname** must be
a site address (`app.example.com`, `http://app.example.com`, `*.example.com`,
`host:port`), and no value may carry a control character. These are not style rules:
the spec is rendered into a Caddy site block and a Quadlet unit, both line-oriented, so
a value that can end its own line writes the next directive. See
[`rendered-config-is-a-boundary.md`](../../decisions/rendered-config-is-a-boundary.md).

How it runs — **blue/green**, rollback-safe. Each app runs as a rootless **systemd
Quadlet** unit under the `steward` user; deploys alternate two colors (`<app>-a` /
`<app>-b`), so the new image is brought up *beside* the live one and only takes over once
it's healthy:

1. Resolve the desired state (stdin envelope or flags) and record it **by digest**
   (`sha256` of the canonical spec, sans secret values) *before* acting.
2. Materialize declared secrets into the Podman secret store (values arrive with the
   deploy, never recorded). See [The app contract](#the-app-contract).
3. Pull the image, and bring up any declared **accessories** — see
   [Accessories](#accessories). They persist across the flip below, so this is a no-op
   whenever their units are unchanged.
4. Run the declared **`release`** command, if any, from the new image — see
   [The release step](#the-release-step). Accessories are up first, because a migration
   with no database to reach is not a migration.
5. Write the **inactive color's** unit on a fresh fixed loopback port (`PORT`, env,
   secret refs, volumes applied), `systemctl --user daemon-reload`, and start it —
   alongside the live color.
6. Health-check the new color on its port **before** any traffic reaches it.
7. Flip Caddy to the new color (write the routing fragment, reload via the admin API).
8. Retire the old color: `systemctl --user stop` drains it (SIGTERM, bounded by the
   unit's `TimeoutStopSec`), then its unit is removed. Save the outgoing image as
   **last-good**.

**The unit carries the container's own ceiling.** Rootless already maps container-root
to the `steward` user rather than the host's, so an escape lands in an unprivileged
account; two directives narrow what is left of it, and both are chosen to cost a
well-behaved image nothing — a hardening default that breaks ordinary apps is one that
gets turned off.

- `NoNewPrivileges=true` blocks the one way a process inside gains a privilege it did
  not start with: a setuid binary or a file capability, at `execve`. Dropping *to* an
  unprivileged user — the `gosu`/`su-exec` entrypoint pattern — is a syscall and not an
  execve gain, so that still works. What stops working is `sudo`.
- `DropCapability=CAP_NET_BIND_SERVICE CAP_SETFCAP CAP_SETPCAP CAP_SYS_CHROOT`.
  **`NET_BIND_SERVICE` is dropped because `deploy` already refuses a port below 1024** —
  the capability is *provably* unused here, so this is a ceiling matching a rule we
  enforce rather than a guess about what apps need. The two are one decision, and
  `TestPortFloorIsWhatJustifiesDroppingNetBindService` fails first if the port floor
  ever moves. `SETFCAP`/`SETPCAP` hand out capabilities and `SYS_CHROOT` is a
  sandbox-escape primitive; none is reachable from serving HTTP. What an ordinary
  entrypoint needs is untouched — `CHOWN` for a data directory, `SETUID`/`SETGID` to
  drop privileges, `KILL` to signal a child.

Both are constants in the renderer — no declared value reaches either — so they join the
directive allowlist `FuzzQuadletUnitShape` asserts, which is what proves a smuggled
`AddCapability` cannot arrive the way `PodmanArgs=--privileged` would.

### One Act on an App at a Time

Every verb that writes an app's state — `deploy`, `rollback`, `start`, `stop`, `restart`,
`remove`, `restore` — takes an exclusive **flock** on `apps/<name>.lock` first. Two
concurrent deploys otherwise read the same active colour, compute the same target, write
the same unit and both flip Caddy, and whichever loses has already torn down the colour the
winner is serving from. The console driving a box while an operator types is the ordinary
case, not the exotic one — the Record makes the same argument for its own flock.

- **Per app, not per box.** Two apps share no state, units or colours, and a release step
  may legitimately run for minutes; a box-wide lock would let one slow migration block
  every other app on the machine.
- **Refused, never queued.** A second act gets `app_busy` (retryable) immediately. Waiting
  would hold an SSH connection open for the length of someone else's deploy.
- **Refused *before* the record**, because nothing was attempted — the same shape as the
  balancer-role refusal beside it. A chain entry for an act that never ran would be the
  record describing something that did not happen.
- **It cannot go stale.** The lock lives on a file descriptor, so the kernel drops it when
  the process exits, including on a kill or a severed connection. There is nothing to
  clean up and **no `unlock` verb to ship** — a lock implemented as a marker file needs
  both, and someone eventually has to judge whether the marker they are looking at is
  real.

The residual race is **port allocation**: two *different* apps deploying at the same
instant can pick the same loopback port, since `pickPort` reads the state of every app and
neither has saved yet. It fails loudly — the second unit will not start, the health check
fails, and the old colour is left running — and it predates the lock. Named here rather
than fixed, because fixing it means a second, box-wide critical section around allocation.

### Processes — the worker, and why it is not a second app

An app may declare **processes**: the worker, the clock, anything it runs that the world
does not reach. Each is the app's **own image, env, secrets and volumes** running a
different command.

That inheritance is the entire point. A worker is not a second app, and if it could be
deployed separately nothing would stop web and worker landing on different digests — a
worker running yesterday's code against today's enqueued jobs, which is a failure the
record could not even describe. One spec, one digest, one deploy: **they cannot skew.**

**A colour is the whole app.** It used to be one container; it is now the web container
plus every declared process, written together, started together and retired together. The
flip is unchanged — one set of containers replaces another — and during the overlap you
have old-web with old-worker and new-web with new-worker, never a mixture. That is also
why a process is blue/green rather than replaced in place: one mechanism, not two.

- **argv, never a shell**, the same rule the release step follows. `Exec=` is quoted per
  element, because systemd splits it on whitespace and an argument containing a space
  would otherwise become two.
- **No published port and no health path.** Nothing reaches a worker and Caddy is never
  told it exists.
- **Verified up, not health-checked.** Nothing can probe a process, but a worker that dies
  on boot would otherwise deploy "successfully" and simply never run — and `Restart=on-failure`
  would hide it as a crash loop. So once the web side is healthy each process unit is asked
  the weakest honest question, *is it still active*; a no tears the colour down and leaves
  the old app serving.
- **It joins the app's network** when there are accessories, for the same reason the web
  container does: a worker that cannot reach the database is not a worker.
- **Lifecycle verbs drive all of it.** `stop web` stops the worker too — stopping an app
  and leaving its worker running would be the same drift arriving by another road.
- **Names cannot collide.** Colours, processes and accessories all mint container names
  from the app's, so `validateState` enumerates every container the app will ever create
  and refuses a duplicate — checking the names rather than the rules that generate them,
  so a new kind of container is covered the day it is added.

**A caveat worth stating:** during the flip both colours' processes run. For a queue
worker that is simply two workers, which is fine. For a **singleton** — a clock or a
recurring scheduler — it briefly is not, and the app is responsible for tolerating that,
the way it already has to tolerate two web containers.

### Accessories

An app may declare **accessories** — the containers it needs on the same box and that
nothing else may reach. A database, a cache. The why and the roads not taken are in
[`decisions/accessories-belong-to-one-app.md`](../../decisions/accessories-belong-to-one-app.md).

Each app with accessories gets a network, `steward-<app>`. The accessory runs on it as
`<app>-<name>` with the alias `<name>`, and **both of the app's colors join the same
network**, so the app dials `db:5432` and a flip does not disturb what the database sees.
Nothing else ever joins — which is the point: declaring that `web` needs a database buys
`web → db` and never `anything → db`. On one box the alternative was the shared host
loopback, which grants both in the same stroke and cannot be narrowed afterwards.

Subordinate by construction:

- **No hostname and no published port.** Caddy does not know it exists, and it is
  reachable on that network and nowhere else — not from another app, not from the host.
  That absence *is* the isolation, so `FuzzAccessoryUnitShape` holds this renderer to the
  same directive allowlist the app's unit obeys.
- **No blue/green.** It holds data on a disk, and two containers over one data directory
  is not a deploy strategy. A single container persists across the app's flips while the
  colors come and go around it — the same rule `replicable?` applies one layer up.
- **Inside the spec digest**, so changing the database's image is a change to the deploy.
- **Its secrets ride the one envelope**, namespaced in the store by container so the app's
  `POSTGRES_PASSWORD` and the database's cannot collide.
- **Its name may not be `a` or `b`** — those are the app's own color suffixes, and a unit
  file would collide.
- **Idempotent.** An accessory whose unit is byte-identical is left running; restarting a
  database nobody asked to change is an outage nobody asked for.
- **`remove` takes them with the app, and never their volumes.** Undeclaring a database
  must not be how its data disappears.

### The Release Step

An app may declare **`release`** — a command run once from the new image before the new
color starts. Migrations are the case it exists for: blue/green means both colors share
the app's volumes and talk to one database, so a schema change has to happen at exactly
one point, with the new code's migrations, and until this there was no such point. The
full reasoning and the roads not taken are in
[`decisions/open/release-command.md`](../../decisions/open/release-command.md); the rules
it holds to:

- **Declared, never passed.** It is a spec field, covered by the spec digest, so the same
  digest always runs the same step. There is no `--release` flag and no `steward exec` —
  a per-invocation command would break what the digest pin guarantees, and a standing exec
  verb would be a shell by another name.
- **argv, never a shell.** `["bin/rails", "db:migrate"]`, exec'd directly. This is
  [`no-key-gets-a-shell.md`](../../decisions/no-key-gets-a-shell.md) one level down: the
  recorded line is unambiguous, and a multi-step release has to live in a script inside
  the image where the digest covers it.
- **Before the new color starts**, which is what makes a failure change nothing — no unit
  written, no color started, the old one still serving. The cost is that the old code
  briefly meets the new schema, so **migrations must be backward-compatible for one
  release**: the expand/contract discipline blue/green requires, not something Steward
  invents.
- **Detached, and not `--rm`.** This is the one step where interruption is worse than
  failure — a dropped SSH connection must not leave a half-applied schema — so the run is
  detached from the connection and polled. It is named after the spec digest, so a retry
  can tell *already running* from *already succeeded* from *failed* instead of running a
  migration twice. Reaped on success; **kept on failure**, because the stopped container
  is the evidence.
- **The app's world, and the app's ceiling.** It runs with the same env, secrets and
  volumes — a migration that cannot reach the database is not a migration — and with the
  same `no-new-privileges` and dropped capabilities the unit carries. A release step is
  not a chance to run with more than the app has, and **Steward builds every flag**; none
  is ever passed through.

It grants no reach the deploy did not already grant: the image's own entrypoint is
arbitrary code by the same author, with the same env and the same volumes. What is new is
a place to write the command down.

If the health check fails, the new color is torn down and the old one stays up and
routed — a failed deploy changes nothing. The full desired state (image, hostnames,
port, health, env, secret *names*, volumes, the active color + per-color ports, and the
spec digest) is persisted in app-state — sans secret values — so Caddy can be rebuilt,
`rollback` re-applies the last-good spec, and the persisted spec is verifiable against
its digest. Loud and recoverable — a failure you see and retry, never a silent
half-deploy.

Because the old color drains rather than being killed at the flip, deploys are
effectively **gapless** for apps that honor the shutdown contract below. Units carry
`Restart=on-failure` and `WantedBy=default.target` (with the `steward` user lingering),
so an app survives crashes and reboots. They also carry `OOMScoreAdjust=100`, so under
memory pressure the kernel sacrifices an app before the control plane (Caddy, sshd, the
record); a retiring color is bumped higher still for its drain, so the live color
outlives it. Per-app resource limits (`MemoryMax`) await a later spec field.

## Routing and HTTPS

Caddy is the box's edge (a root service on :80/:443); a deploy only writes a
steward-owned routing fragment and reloads Caddy through its local admin API (step 5
above). **Automatic HTTPS comes for free:** for any hostname whose DNS A/AAAA points at
the box and whose :80/:443 are reachable, Caddy obtains and serves a genuine **Let's
Encrypt** certificate over ACME — no cert config in the deploy. The certificate is tied
to the hostname, not the color, so it survives a blue/green flip (reused, not
re-requested). A box with no real domain deploys against an `http://` hostname instead.

This holds under the rootless model: the certs are Caddy's (root), the routing fragment
is the `steward` user's, and the two meet only through the admin-API reload — no root in
the deploy loop. *Behind a TLS-terminating CDN/proxy* (e.g. Cloudflare orange cloud) the
edge serves its own cert and intercepts the ACME challenge; that topology needs DNS-01
and stays open (see [Open](#open)).

### Pruning — the image store is a cache, not a record

A deploy pulls a new image and the old one stays. Nothing removed it, and a box that
deploys often fills its disk with layers nobody can name — the most common way an
otherwise healthy unattended machine dies.

**The record is the spec, not the blob.** An app's spec names its image by *digest*;
`backup` captures that spec and `restore` replays it through the same deploy path, so a
restored box **re-pulls** what it needs. Because the reference is a digest rather than a
tag, what comes back is byte-identical. An evicted image is therefore not lost — it is
evicted — and pruning is not destruction.

So a successful deploy, after the flip and after the old colour is retired, drops every
local image no app still references. **Two are kept per app:**

| Kept | Why |
|---|---|
| `Image` | what the active colour is running |
| `PrevImage` | what `rollback` re-deploys |

`PrevImage` stays local even though `restore` could re-pull it, because the two recoveries
have different risk profiles. A restore is *planned* — you can arrange for a reachable
registry. A rollback happens at 3am with something already broken, and the last thing it
should need is the network. One bounded extra image buys that.

Three properties hold this safe:

- **It never fails a deploy.** Cleanup that can break the act it follows is worse than the
  garbage it collects; the prune runs last and its failures are silent.
- **`podman rmi` is called without `--force`.** Podman refuses to remove an image any
  container still uses, even a stopped one — so the worst case for an image we misjudged
  is a refusal we ignore, never a running app losing its layers.
- **Images are matched by ID, not by reference string.** The same image can be named by
  tag, by digest, or through a repository since renamed; only the ID is stable.

`doctor` reports the read-only half — how many images the box holds and how many are
unreferenced — and prescribes. It never prunes: it is an observe verb running
unprivileged, and a read that quietly changed the box is the one thing this design
refuses.

### `steward route` — fronting other boxes

Every route above is `reverse_proxy 127.0.0.1:<port>`: an app on *this* box, derived from
what is deployed here. That cannot express the other shape — one box fronting several
others — so `route` adds it.

```
steward route < table.json
{"routes":[{"hostnames":["app.example.com"],"upstreams":["10.0.0.5:8080","10.0.0.6:8080"]}]}
```

- **A second fragment, not a second Caddy.** It writes `/etc/caddy/steward/routes.caddy`,
  which the base config already picks up — `prepare` writes `import
  /etc/caddy/steward/*.caddy`, a glob, so the extension point predates the verb. Apps own
  `apps.caddy` and routes own `routes.caddy`; neither can clobber the other, and both
  reload through the same admin API with no root.
- **Declarative and wholly replaced**, like `deploy`: you send the table the box should
  serve, and that becomes what it serves. There is no add-a-route or drop-a-route, because
  a partial edit needs caller and box to agree about a starting state neither can see.
  An **empty table is valid** and means "front nothing" — that is how a box leaves service.
- **Validated before it is written.** A refused table leaves the previous fragment in
  place, so the box keeps serving what it was serving rather than losing its routes to a
  malformed request. A hostname in two routes is refused rather than silently resolved,
  and an upstream must carry a port — there is no default worth guessing.
- **Not secret.** Upstream addresses ride the recorded envelope, not the off-record
  channel: what a box fronts is exactly the sort of thing the record should answer later.
- `status` reports `routes` — read back off the fragment, so a control plane compares what
  the box *is* fronting against the table it believes it sent, rather than assuming.

Several upstreams on one directive is what makes Caddy balance across them. This is the
box half of the console's Balancer role
([`one-primitive-composed.md`](../../decisions/one-primitive-composed.md)); nothing here
knows about a fleet, and the box is told its table by a named actor like everything else.

## `steward rollback <app>`

Re-deploy the last-good image. Same path as `deploy`.

## Lifecycle

Lifecycle drives the active color's user service through `systemctl --user`. `stop`
matches operator intent — it **stays down across reboot** (the unit is rewritten without
its `[Install]` section, since a generated Quadlet unit can't be `systemctl disable`d);
`start` re-enables and brings it back.

| Command | Does |
|---|---|
| `steward start <app>` | Boot-enable the active color and start it. |
| `steward stop <app>` | Stop it and keep it down across reboot. |
| `steward restart <app>` | Restart the active color in place. |
| `steward remove <app>` | Stop and remove both colors' units, secrets, and state. |
| `steward route` | Replace this box's table of routes to *other* boxes (table on stdin). |

## Backup & restore

Encrypted, deduplicated backups via **restic** — a single static binary, like Steward.
restic encrypts client-side with an **operator-held key**, so the destination only ever
sees ciphertext; the repo can live on any S3 / SFTP / self-hosted store (even hostile
infra) and stay sovereign. The repo URL lives in `/var/lib/steward/backup.json`; the
password lives in `/var/lib/steward/secrets/restic` (`0600`) and reaches restic via
`RESTIC_PASSWORD_FILE`, never argv. The *why* is in
[`decisions/backup.md`](../../decisions/backup.md).

| Command | Does |
|---|---|
| `steward backup --repo <url>` | One-time: set the repo, read the password on **stdin**, init it. |
| `steward backup <app>` · `--all` | Snapshot an app's declared **volumes** + its digest-tagged spec (self-contained: data + how to redeploy). `--all` does every app. |
| `steward backup --machine` | Snapshot Steward's own record dir off-box (record, status, hardening, app specs) — **excluding `secrets/`**. The snapshot-grade half of off-host shipping. |
| `steward restore <app>` · `--machine` | Rehydrate the volumes/record from the latest snapshot, then redeploy the app on its pinned image. |

A restore writes into the live filesystem, and the paths it writes come from the
snapshot — so it is **confined to what the app declared**: its volumes and its spec
file, and nothing else in the snapshot is extracted. Unbounded, a repo could drop a file
anywhere the steward user can write, and `~steward/.ssh/authorized_keys` is a `grant`
grant. The restored spec is validated like any other input before it is acted on.

Backup is **generic over volumes**: a named volume is resolved to its podman mountpoint,
a bind mount to its host path. Steward is **database-agnostic** — it never runs
`pg_dump`; an app that needs a consistent dump declares a backup hook (below).

**Secrets are never in a backup.** They live host-side in the podman secret store and are
re-suppliable; restore brings back image + config + data, and the operator re-provides
secret values via the deploy envelope. So a backup repo never holds plaintext secrets.

## `steward apply-updates`

Apply machine OS package updates.

---

## The app contract

An app **listens on `--port`** (default 8080) inside the container and **answers a
health check at `--health`** (default `/`) with a non-5xx status before it takes
traffic. Steward injects `PORT`, publishes the container on a loopback port, and proxies
the app's hostname(s) to it through Caddy.

**Config, secrets, and volumes** are part of the declared spec (above):

- **Config (`env`)** is plain `-e NAME=value`, recorded with the deploy.
- **Secrets** are declared by *name* and delivered through the **Podman secret store**
  (`--secret <app>__<NAME>,type=env,target=<NAME>`); values arrive on stdin and never
  ride argv, never land in `podman inspect`. `podman secret ls` is a names-only ledger,
  mirroring `authorized_keys`. Rotation is `rm`+create, which a redeploy does for free.
- **Secret files** (`secret_files`) are the same store and the same stdin delivery, but
  *mounted as a file* instead of injected as env: a map of secret **name → absolute
  container path** (`"config": "/etc/zot/config.json"`), emitted as
  `--secret …,type=mount,target=<path>`. For apps configured by a file (a registry's
  `config.json`, an htpasswd) rather than env vars. The path is recorded config; the
  value never is.
- **Volumes** are `name:/path` mounts for the app's persistent data. A **named volume**
  is unrestricted. A **bind mount** must live under the data root (`/srv` by default;
  `STEWARD_BIND_ROOTS` to change it) — an app declaring a host path can otherwise mount
  the files that confer privilege (`~steward/.ssh`, the Quadlet dir) and step over the
  scope ladder. See
  [`rendered-config-is-a-boundary.md`](../../decisions/rendered-config-is-a-boundary.md).
- **Backup hook (`backup`)** is an optional command run *inside the container* before a
  snapshot, so a stateful app makes itself consistent — e.g. `pg_dump -Fc -f
  /data/dump.pgc`, or `sqlite3 app.db ".backup /data/app.bak"` — writing into a declared
  volume that then gets backed up. Steward stays database-agnostic; the app owns its own
  consistency.

The why — and the roads not taken — is in
[`decisions/declarative-deploy.md`](../../decisions/declarative-deploy.md). (The old
`APP_CONTRACT.md` in `switchyard-platform` is a reference to mine, not a spec to copy.)

An app must also:

- **Bind `0.0.0.0`, not loopback.** Steward publishes the container's port on a host
  loopback address; that only reaches the app if it listens on all interfaces *inside*
  the container.
- **Use an unprivileged port (1024–65535).** The container runs as its image's non-root
  user, so it can't bind a port below 1024. Steward rejects a privileged port rather
  than let it fail cryptically at startup.
- **Not run its own edge proxy.** Caddy is the platform's edge — it terminates TLS,
  speaks HTTP/2, and routes hostnames; a second proxy inside the container is redundant
  and fights for ports. If your image bundles one — Rails' default image ships
  **Thruster** — either run the app server directly (e.g. `CMD ["./bin/rails",
  "server", "-b", "0.0.0.0"]`), or point Thruster at the deploy port: set `HTTP_PORT` to
  your `--port` and keep it different from Thruster's `TARGET_PORT` (default `3000`) —
  e.g. a deploy port of `4000`. Equal ports collide on 3000 and 502-loop.
- **Drain on `SIGTERM`, then exit.** At the blue/green flip the old color is sent
  `SIGTERM` and given the unit's `TimeoutStopSec` (default 30s) to finish: stop accepting
  new connections, complete in-flight requests, send any websockets a `1001 "going away"`
  close (clients reconnect onto the new color via Caddy), then exit. An app that exits
  cleanly makes the deploy gapless; one that ignores `SIGTERM` is cut at the timeout —
  the bounded, degraded fallback. There is no live-connection migration across colors
  (no proxy can do it), so a deploy always *reconnects* websocket clients; the contract
  just makes that graceful.

## Private registries

A public image just pulls. A **private** one needs a credential — and that credential is
**box state, not part of any app**: it's shared by every app pulling from the registry
and outlives any one of them, so it's modeled like `authorize`/`revoke`, not like a
deploy field.

- `steward registry-login <registry> --username <user>` reads the password on **stdin**
  (never argv — only the registry and username are recorded) and writes a persistent
  rootless login (`REGISTRY_AUTH_FILE` under the steward user, surviving reboot). Every
  later pull reuses it. `registry-logout` is the explicit, recorded counterweight; a
  login is **never** removed as a side effect of `remove` (another app may share it).
- **Legible:** `status` lists the registries the box is logged into (host + username,
  secret redacted); `doctor` reports which app registries have a login.
- **Failure is bounded.** A deploy pulls only when the digest isn't already on the box,
  so restart, reboot recovery, and rollback-to-a-cached-image never need the registry —
  an expired credential's blast radius is exactly "introduce a *new* image". A failed
  pull is classified (`registry_auth` / `registry_unreachable` / `image_not_found`) and
  leaves the running app untouched; the `registry_auth` message names the registry and
  points at `registry-login`.
- **v1 is static credentials only** (PAT / password / htpasswd). Short-lived-token
  registries (ECR, GCP Artifact Registry) want a credential helper — deferred.

The why and the roads not taken are in
[`registry-credentials.md`](../../decisions/registry-credentials.md).

## Open

Open questions for deploy & lifecycle are kept out of the spec, in
[`steward-open-questions.md`](../../decisions/open/steward-open-questions.md) — HTTPS
behind a TLS-terminating CDN. (Direct-domain automatic HTTPS is
specified above; gapless cutover and the container user model are now settled — see
[`quadlet-deploy.md`](../../decisions/quadlet-deploy.md) and
[`ceiling-is-the-machine.md`](../../decisions/ceiling-is-the-machine.md).) When one
settles, its answer moves into this spec and its reasoning into `decisions/`.
