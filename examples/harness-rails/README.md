# harness-rails

A tiny Rails app whose only job is to **exercise the Vilice deploy contract**. One
published image (`ghcr.io/agoraforge/harness-rails`) behaves differently per env var, so a
single artifact covers most axes of a deploy: health timing, env config, env *and* file
secrets, a volume-backed counter, a crash, and a memory balloon. It's the workhorse of the
demo App Library — the integration test you can actually deploy.

It honours the contract: runs **non-root**, listens on **`PORT` (default 8080)** on
`0.0.0.0`, speaks plain HTTP (the platform's Caddy is the edge), and ships **no master
key** (stateless; production uses an ephemeral `SECRET_KEY_BASE_DUMMY`).

## Endpoints

| Route | What it returns |
|---|---|
| `GET /` | hello — app, version, stack, hostname, pid, uptime, and echoed `DEMO_*` env |
| `GET /healthz` | `200` when ready, `503` while starting or failing (the health gate) |
| `GET /secret` | whether the env and file secrets arrived — **never the values** |
| `GET /counter` | increments a counter under `DATA_DIR` (persists iff the volume does) |

## Knobs → coverage axes

| Env var | Behavior | Axis it proves |
|---|---|---|
| `DEMO_*` | echoed at `/` | plain env delivery |
| `HEALTH_DELAY=20s` | not ready until N seconds after boot | health gate waits for a slow starter |
| `HEALTH_FAIL=1` | never ready (`/healthz` always 503) | deploy **rolls back safely**, never flips |
| `SECRET_TOKEN=…` | `/secret` reports env secret present | env secret channel (off-record) |
| `SECRET_FILE=/path` | `/secret` reports file secret present | **file-mount secret** |
| `DATA_DIR=/data` | where `/counter` persists | volume survives the blue/green flip |
| `CRASH_AFTER=30s` | exits non-zero after N seconds | `Restart=on-failure` |
| `BALLOON_MB=400` | holds N MB resident at boot | `MemoryMax` / OOM |
| (built-in) | Puma drains in-flight requests on `SIGTERM` | HTTP drain on cutover |

Durations accept `20`, `20s`, or `500ms`.

> **Not yet covered:** a websocket endpoint (`/ws`) that holds a connection and sends a
> `1001` close on `SIGTERM` — the explicit websocket-drain axis. Puma already drains HTTP
> on cutover; the websocket case is a planned second pass (needs ActionCable).

## Build & publish

```sh
make build    # native-arch image, quick local check
make push     # multi-arch (amd64 + arm64) → ghcr.io/agoraforge/harness-rails
```

The devbox is amd64; build a matching arch (or a multi-arch manifest) before deploying to it.

## Deploy

`deploy.sh` resolves the image digest on the box, builds the desired-state envelope from
whichever knobs you set, and pipes it to `vilice deploy` over scoped SSH (same pattern as
`examples/zot/`):

```sh
examples/harness-rails/deploy.sh --ssh devbox                  # plain hello
HEALTH_FAIL=1   examples/harness-rails/deploy.sh --ssh devbox   # watch a deploy refuse to flip
SECRET_TOKEN=shh examples/harness-rails/deploy.sh --ssh devbox  # env secret
SECRET_FILE=hi   examples/harness-rails/deploy.sh --ssh devbox  # file-mount secret
VOLUME=1        examples/harness-rails/deploy.sh --ssh devbox   # persistent /counter
```
