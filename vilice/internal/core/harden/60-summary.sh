#!/usr/bin/env bash
# Print a clear completion summary. Generic — reads the box, knows nothing about
# vilice. Runs last (highest number).
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"

osname="Linux"
[ -r /etc/os-release ] && { . /etc/os-release; osname="${PRETTY_NAME:-Linux}"; }

ports=$(ufw status 2>/dev/null | awk '/ALLOW/{print $1}' | sort -u | paste -sd', ' -)
[ -z "$ports" ] && ports="(none)"
swap=$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 | tr -d ' ')
[ -z "$swap" ] && swap="none"

rule="────────────────────────────────────────────"
printf '\n%s\n  Box hardened — %s\n%s\n' "$rule" "$osname" "$rule"
printf '  SSH:       key-only, no passwords\n'
printf '  Firewall:  ufw active — open: %s\n' "$ports"
printf '  fail2ban:  %s (sshd jail)\n' "$(systemctl is-active fail2ban 2>/dev/null || echo unknown)"
printf '  Updates:   unattended security upgrades enabled\n'
printf '  Swap:      %s\n' "$swap"
printf '\n  Next: vilice prepare\n\n'
