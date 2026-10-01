#!/usr/bin/env bash
# Persistent journald with a size cap, so logs survive reboots without filling disk.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

mkdir -p /etc/systemd/journald.conf.d
CONF="/etc/systemd/journald.conf.d/10-harden.conf"
read -r -d '' DESIRED <<EOF || true
[Journal]
Storage=persistent
SystemMaxUse=500M
EOF

if [ -f "$CONF" ] && diff -q <(echo "$DESIRED") "$CONF" >/dev/null 2>&1; then
  ok "journald already configured"
else
  echo "$DESIRED" > "$CONF"; chmod 644 "$CONF"
  systemctl restart systemd-journald
  ok "journald persistent (cap 500M)"
fi
