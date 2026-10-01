#!/usr/bin/env bash
# Deploy zot (a private OCI registry) to a Vilice box — a real test of the file-secrets
# affordance: zot's config.json and htpasswd are delivered as *file* secrets (mounted),
# not env vars. Reuses the devbox you set up with script/devbox.sh.
#
#   ZOT_PASS=secret examples/zot/deploy.sh --ssh devbox
#   ZOT_HOSTNAME=registry.example.com ZOT_PASS=secret examples/zot/deploy.sh --ssh devbox
#
# Needs: the `--ssh <alias>` admin login (to resolve the image digest via podman) and the
# scoped dev key (to deploy as the _vilice user). `htpasswd` (apache2-utils) and `python3`.
set -euo pipefail

ALIAS=""; [ "${1:-}" = "--ssh" ] && { ALIAS="${2:-}"; shift 2 || true; }
[ -n "$ALIAS" ] || { echo "usage: ZOT_PASS=… $0 --ssh <devbox-alias>"; exit 1; }

KEY="${DEVBOX_KEY:-$HOME/.vilice-devbox/id_ed25519}"
KNOWN="$(dirname "$KEY")/known_hosts"
APP="${ZOT_APP:-zot}"
TAG="${ZOT_TAG:-ghcr.io/project-zot/zot-linux-amd64:latest}"
ZUSER="${ZOT_USER:-admin}"
PASS="${ZOT_PASS:?set ZOT_PASS (the registry password)}"
DIR="$(cd "$(dirname "$0")" && pwd)"
kh=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN")

command -v htpasswd >/dev/null || { echo "need 'htpasswd' (apt install apache2-utils)"; exit 1; }
command -v python3  >/dev/null || { echo "need python3"; exit 1; }

# Resolve the box's real hostname from the ssh alias (for the scoped connection + a
# default registry hostname when you haven't pointed a domain yet).
HOST="$(ssh -G "$ALIAS" | awk '$1=="hostname"{print $2; exit}')"
HOSTNAME_="${ZOT_HOSTNAME:-http://$HOST}"   # real domain → HTTPS; http://<ip> → plain, no DNS needed

# Pin the image by digest. Resolve it via the admin's (rootful) podman — the manifest
# digest is registry-addressed, so it's the same one the _vilice user will pull at deploy.
echo "• resolving $TAG digest on the box…"
digest="$(ssh "${kh[@]}" "$ALIAS" \
  "podman pull -q '$TAG' >/dev/null && podman image inspect '$TAG' --format '{{.Digest}}'")"
image="${TAG%:*}@$digest"
echo "  → $image"

echo "• generating htpasswd for '$ZUSER'…"
htline="$(htpasswd -nbB "$ZUSER" "$PASS")"

echo "• deploying '$APP' to $HOSTNAME_ (config + htpasswd as file secrets)…"
CONFIG="$(cat "$DIR/config.json")" IMAGE="$image" HOST_="$HOSTNAME_" HTLINE="$htline" python3 - <<'PY' \
  | ssh -i "$KEY" -o IdentitiesOnly=yes "${kh[@]}" "_vilice@$HOST" "deploy $APP"
import json, os
print(json.dumps({
    "app": {
        "image": os.environ["IMAGE"],
        "hostnames": [os.environ["HOST_"]],
        "port": 5000,
        "health": "/v2/",
        "volumes": ["zot-data:/var/lib/registry:U"],   # :U → podman chowns the volume to zot's user
        "secret_files": {
            "config":   "/etc/zot/config.json",
            "htpasswd": "/etc/zot/htpasswd",
        },
    },
    "secret_values": {
        "config":   os.environ["CONFIG"],
        "htpasswd": os.environ["HTLINE"] + "\n",
    },
}))
PY

echo
echo "Deployed. Check it:"
echo "  script/devbox.sh ssh status --ssh $ALIAS"
echo "  script/devbox.sh ssh 'logs $APP' --ssh $ALIAS      # if it didn't come up"
echo "  curl -u $ZUSER:<pass> https://$HOSTNAME_/v2/_catalog   # once DNS/HTTPS is live"
