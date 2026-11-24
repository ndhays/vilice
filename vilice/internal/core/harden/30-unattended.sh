#!/usr/bin/env bash
# Automatic patches via unattended-upgrades, from Debian's own two origins: the
# security archive, and the stable release's point updates (where Debian puts the
# security fixes too minor for an advisory). Nothing else: not -updates, not
# backports, not third-party repos like Caddy's. A maintenance window handles reboots
# when an update needs one. Manual/full upgrades stay
# deliberate (that's `vilice apply-updates`).
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

info "waiting for apt to be idle"
wait_for_apt 180 || { fail "apt is busy"; exit 1; }

if pkg_installed unattended-upgrades; then
  ok "unattended-upgrades installed"
else
  apt-get install -y -qq unattended-upgrades
  ok "unattended-upgrades installed"
fi

# A higher-priority drop-in that overrides only what we care about — leaves the
# package's shipped 50unattended-upgrades intact.
OVERRIDE="/etc/apt/apt.conf.d/52-harden-unattended"
PERIODIC="/etc/apt/apt.conf.d/20auto-upgrades"

read -r -d '' DESIRED_OVERRIDE <<EOF || true
// Generic harden policy: Debian security + point updates, auto-reboot in a window.
// The lists are cleared first, so this file is the whole policy whatever the package's
// 50unattended-upgrades says (apt appends list entries across files).
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
  "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
  "origin=Debian,codename=\${distro_codename},label=Debian";
};
Unattended-Upgrade::Automatic-Reboot "$UNATTENDED_REBOOT";
Unattended-Upgrade::Automatic-Reboot-Time "$UNATTENDED_REBOOT_TIME";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Random-Sleep "$UNATTENDED_RANDOM_SLEEP";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

read -r -d '' DESIRED_PERIODIC <<EOF || true
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

if [ -f "$OVERRIDE" ] && diff -q <(echo "$DESIRED_OVERRIDE") "$OVERRIDE" >/dev/null 2>&1; then
  ok "unattended override already current"
else
  echo "$DESIRED_OVERRIDE" > "$OVERRIDE"; chmod 644 "$OVERRIDE"
  ok "wrote $OVERRIDE"
fi
if [ -f "$PERIODIC" ] && diff -q <(echo "$DESIRED_PERIODIC") "$PERIODIC" >/dev/null 2>&1; then
  ok "periodic config already current"
else
  echo "$DESIRED_PERIODIC" > "$PERIODIC"; chmod 644 "$PERIODIC"
  ok "wrote $PERIODIC"
fi

for timer in apt-daily.timer apt-daily-upgrade.timer; do
  systemctl enable --now "$timer" >/dev/null 2>&1 || true
done
# What apt actually loaded, not what we wrote: both Debian origins are in, and nothing
# is left of the package's Allowed-Origins. (A later drop-in may add an origin of its
# own, as prepare does for Caddy's repo.)
dump="$(apt-config dump)"
if printf '%s\n' "$dump" | grep -q "Unattended-Upgrade::Automatic-Reboot \"$UNATTENDED_REBOOT\"" \
   && printf '%s\n' "$dump" | grep -q 'codename=[a-z]*-security,label=Debian-Security"' \
   && printf '%s\n' "$dump" | grep -q 'codename=[a-z]*,label=Debian"' \
   && ! printf '%s\n' "$dump" | grep -q '^Unattended-Upgrade::Allowed-Origins:: '; then
  ok "unattended-upgrades configured (Debian security + point updates)"
else
  fail "unattended-upgrades config did not load"
  exit 1
fi
