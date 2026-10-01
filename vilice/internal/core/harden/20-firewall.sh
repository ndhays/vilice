#!/usr/bin/env bash
# UFW firewall + fail2ban.
#   UFW: default deny inbound, allow outbound, allow sshd's port and nothing else.
#   Web ports (80/443) are opened by `prepare <role>` — see blueprint/vilice/provision.md.
#   fail2ban: ban hosts that fail sshd auth repeatedly.
# Ports are allowed BEFORE UFW is enabled, to avoid locking out the live session.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

info "waiting for apt to be idle"
wait_for_apt 180 || { fail "apt is busy"; exit 1; }

NEEDED=()
for p in ufw fail2ban; do
  pkg_installed "$p" && ok "$p installed" || NEEDED+=("$p")
done
if [ ${#NEEDED[@]} -gt 0 ]; then
  info "installing: ${NEEDED[*]}"
  apt-get update -qq
  apt-get install -y -qq "${NEEDED[@]}"
  ok "packages installed"
fi

# --- UFW rules (add before enabling) ---
# sshd's actual port, never the constant 22 — a rule that assumes 22 locks you out of
# a box reached on 2222, and a remote lockout has no repair.
ALLOW=("$SSH_PORT")
for port in "${ALLOW[@]}"; do
  if ufw status | grep -qE "^${port}(/tcp)?\s+ALLOW"; then
    ok "ufw already allows $port"
  else
    ufw allow "$port/tcp" >/dev/null
    ok "ufw allow $port"
  fi
done
if ufw status | grep -q "Status: active"; then
  ok "ufw already active"
else
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw --force enable >/dev/null
  ok "ufw enabled (deny inbound, allow outbound)"
fi

# --- fail2ban sshd jail ---
JAIL="/etc/fail2ban/jail.local"
read -r -d '' DESIRED <<EOF || true
[DEFAULT]
banaction = ufw
banaction_allports = ufw
bantime  = $FAIL2BAN_BAN_TIME
findtime = $FAIL2BAN_FIND_TIME
maxretry = $FAIL2BAN_MAX_RETRY

[sshd]
enabled = true
port    = $SSH_PORT
backend = systemd
EOF
if [ -f "$JAIL" ] && diff -q <(echo "$DESIRED") "$JAIL" >/dev/null 2>&1; then
  ok "fail2ban jail.local already current"
else
  echo "$DESIRED" > "$JAIL"
  chmod 644 "$JAIL"
  ok "wrote $JAIL"
fi
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
sleep 1
if fail2ban-client status sshd >/dev/null 2>&1; then
  ok "fail2ban sshd jail active"
else
  fail "fail2ban sshd jail not active"
  exit 1
fi
