#!/usr/bin/env bash
# Verify the posture the harden steps apply, and print it as one JSON object.
# Generic — reads the box, knows nothing about vilice (no _vilice user, no record,
# no Podman). The counterpart to the apply steps: each boolean here mirrors a step.
#
# Has no NN- digit prefix, so the apply runner (stepScripts) never runs it as a step —
# the same reason common.sh is skipped. vilice invokes it directly for `harden --check`.
#
# Needs root for an authoritative read: `sshd -T` (effective sshd config) and `ufw
# status` both require it. Run as non-root, the SSH/firewall facts would be guesses.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"

# true/false helper: echo a JSON boolean for a shell success/failure.
jbool() { if "$@" >/dev/null 2>&1; then printf 'true'; else printf 'false'; fi; }

# --- 10-ssh: root login + password auth off (authoritative via sshd -T) ---
sshd_eff="$(sshd -T 2>/dev/null || true)"
root_login="$(printf '%s\n' "$sshd_eff" | awk '/^permitrootlogin /{print $2}')"
passwd_auth="$(printf '%s\n' "$sshd_eff" | awk '/^passwordauthentication /{print $2}')"
# Hardened = root login is not allowed (no / forced-commands-only / prohibit-password
# all close password+shell root SSH) and password auth is off.
case "$root_login" in no|forced-commands-only|prohibit-password) ssh_root=true ;; *) ssh_root=false ;; esac
[ "$passwd_auth" = "no" ] && ssh_pass=true || ssh_pass=false

# --- 20-firewall: ufw active, fail2ban running ---
ufw_active=false
ufw status 2>/dev/null | grep -qi '^Status: active' && ufw_active=true
fail2ban=$(jbool systemctl is-active --quiet fail2ban)

# Allowed ports, for the open-port narrative (best-effort).
ports=$(ufw status 2>/dev/null | awk '/ALLOW/{print $1}' | sort -u | paste -sd',' - || true)

# --- 30-unattended: security auto-updates configured ---
unattended=false
if pkg_installed unattended-upgrades \
   && grep -rqs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/ 2>/dev/null; then
  unattended=true
fi

printf '{"ssh_root_login_disabled":%s,"password_auth_disabled":%s,"firewall_active":%s,"fail2ban_active":%s,"unattended_upgrades":%s,"open_ports":"%s"}\n' \
  "$ssh_root" "$ssh_pass" "$ufw_active" "$fail2ban" "$unattended" "$ports"
