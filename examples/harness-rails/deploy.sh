#!/usr/bin/env bash
# Deploy the harness app to a Steward box — and, via env knobs, pick which axis of the
# deploy contract to exercise. Mirrors examples/zot/deploy.sh: resolve the image digest on
# the box, build the desired-state envelope, pipe it to `steward deploy` over scoped SSH.
#
#   examples/harness-rails/deploy.sh --ssh devbox                       # plain hello
#   HEALTH_DELAY=20s examples/harness-rails/deploy.sh --ssh devbox      # slow-boot health gate
#   HEALTH_FAIL=1 examples/harness-rails/deploy.sh --ssh devbox         # never-ready → rollback safety
#   SECRET_TOKEN=shh examples/harness-rails/deploy.sh --ssh devbox      # env secret (off-record)
#   SECRET_FILE=hello examples/harness-rails/deploy.sh --ssh devbox     # file-mount secret
#   VOLUME=1 examples/harness-rails/deploy.sh --ssh devbox              # persistent counter (/counter)
#   CRASH_AFTER=30s examples/harness-rails/deploy.sh --ssh devbox       # restart-on-failure
#   BALLOON_MB=400 examples/harness-rails/deploy.sh --ssh devbox        # memory pressure / OOM
#
# Needs: the `--ssh <alias>` admin login (to resolve the digest via podman) and the scoped
# dev key (to deploy as the steward user). Reuses script/devbox.sh's key layout.
set -euo pipefail

ALIAS=""; [ "${1:-}" = "--ssh" ] && { ALIAS="${2:-}"; shift 2 || true; }
[ -n "$ALIAS" ] || { echo "usage: $0 --ssh <devbox-alias>  [knobs as env vars]"; exit 1; }

KEY="${DEVBOX_KEY:-$HOME/.steward-devbox/id_ed25519}"
KNOWN="$(dirname "$KEY")/known_hosts"
APP="${HARNESS_APP:-harness}"
TAG="${HARNESS_TAG:-ghcr.io/agoraforge/harness-rails:latest}"
kh=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN")

command -v python3 >/dev/null || { echo "need python3"; exit 1; }

HOST="$(ssh -G "$ALIAS" | awk '$1=="hostname"{print $2; exit}')"
HOSTNAME_="${HARNESS_HOSTNAME:-http://$HOST}"   # real domain → HTTPS; http://<ip> → plain, no DNS

echo "• resolving $TAG digest on the box…"
digest="$(ssh "${kh[@]}" "$ALIAS" \
  "podman pull -q '$TAG' >/dev/null && podman image inspect '$TAG' --format '{{.Digest}}'")"
image="${TAG%:*}@$digest"
echo "  → $image"

# Build the envelope from whichever knobs are set. Plain env (DEMO_/HEALTH_/CRASH_/BALLOON_)
# is recorded config; SECRET_TOKEN rides as an env secret and SECRET_FILE as a mounted file
# secret — both values arrive on stdin and are never recorded.
echo "• deploying '$APP' to $HOSTNAME_…"
IMAGE="$image" HOST_="$HOSTNAME_" \
HEALTH_DELAY="${HEALTH_DELAY:-}" HEALTH_FAIL="${HEALTH_FAIL:-}" \
CRASH_AFTER="${CRASH_AFTER:-}" BALLOON_MB="${BALLOON_MB:-}" \
DEMO_GREETING="${DEMO_GREETING:-hello from the harness}" \
SECRET_TOKEN="${SECRET_TOKEN:-}" SECRET_FILE="${SECRET_FILE:-}" VOLUME="${VOLUME:-}" \
python3 - <<'PY' | ssh -i "$KEY" -o IdentitiesOnly=yes "${kh[@]}" "steward@$HOST" "deploy $APP"
import json, os

env = {"DEMO_GREETING": os.environ["DEMO_GREETING"]}
for k in ("HEALTH_DELAY", "HEALTH_FAIL", "CRASH_AFTER", "BALLOON_MB"):
    if os.environ.get(k):
        env[k] = os.environ[k]

app = {
    "image": os.environ["IMAGE"],
    "hostnames": [os.environ["HOST_"]],
    "port": 8080,
    "health": "/healthz",
    "env": env,
}

secret_values = {}
if os.environ.get("SECRET_TOKEN"):
    app["secrets"] = ["SECRET_TOKEN"]
    secret_values["SECRET_TOKEN"] = os.environ["SECRET_TOKEN"]
if os.environ.get("SECRET_FILE"):
    app["secret_files"] = {"DEMO_FILE": "/run/secrets/demo"}
    app["env"]["SECRET_FILE"] = "/run/secrets/demo"   # tell the app where to read it
    secret_values["DEMO_FILE"] = os.environ["SECRET_FILE"]
if os.environ.get("VOLUME"):
    app["volumes"] = ["harness-data:/data"]
    app["env"]["DATA_DIR"] = "/data"

print(json.dumps({"app": app, "secret_values": secret_values}))
PY

echo
echo "Deployed. Check it:"
echo "  curl http://$HOST/                       # hello + echoed env"
echo "  curl http://$HOST/secret                 # which secrets arrived (values never shown)"
echo "  curl http://$HOST/counter                # increments; persists iff VOLUME=1"
echo "  script/devbox.sh ssh status --ssh $ALIAS"
