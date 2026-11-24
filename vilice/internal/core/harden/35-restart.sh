#!/usr/bin/env bash
# Restart services after an update replaces a library they use, with needrestart.
# Without it a patched library sits on disk while long-running daemons (sshd, fail2ban,
# journald) keep the old one in memory; Debian's reboot flag fires mostly for kernels,
# so the reboot window would not catch it.
#
# Automatic ('a'), because the update that triggers it is unattended: with no terminal,
# needrestart's default only lists. Its own defaults never restart user@*.service, dbus
# or logind, so the containers under a user's systemd are left running.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

info "waiting for apt to be idle"
wait_for_apt 180 || { fail "apt is busy"; exit 1; }

if pkg_installed needrestart; then
  ok "needrestart installed"
else
  apt-get install -y -qq needrestart
  ok "needrestart installed"
fi

CONF="/etc/needrestart/conf.d/50-harden.conf"
read -r -d '' DESIRED <<'CONF' || true
# Generic harden policy: restart outdated services without asking.
$nrconf{restart} = 'a';
CONF
if [ -f "$CONF" ] && diff -q <(echo "$DESIRED") "$CONF" >/dev/null 2>&1; then
  ok "needrestart already automatic"
else
  mkdir -p "$(dirname "$CONF")"
  echo "$DESIRED" > "$CONF"; chmod 644 "$CONF"
  ok "wrote $CONF"
fi
