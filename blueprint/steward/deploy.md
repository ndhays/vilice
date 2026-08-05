# Steward — Deploy & Lifecycle

Putting an app on the box and running it. This is the **wide, not deep** part: a state
machine whose failures are loud and recoverable. The deep parts are borrowed — Caddy
routes traffic and handles TLS, Podman runs the container. Everything here runs under
`operate` scope ([auth.md](auth.md)) and writes its record first ([record.md](record.md)).

**Status:** Canonical. Last touched 2026-08-02.

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
    "volumes": ["app-data:/rails/storage"]
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
3. Pull the image; write the **inactive color's** unit on a fresh fixed loopback port
   (`PORT`, env, secret refs, volumes applied), `systemctl --user daemon-reload`, and
   start it — alongside the live color.
4. Health-check the new color on its port **before** any traffic reaches it.
5. Flip Caddy to the new color (write the routing fragment, reload via the admin API).
6. Retire the old color: `systemctl --user stop` drains it (SIGTERM, bounded by the
   unit's `TimeoutStopSec`), then its unit is removed. Save the outgoing image as
   **last-good**.

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
