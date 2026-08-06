#!/usr/bin/env bash
# Shared helpers and tunables for the harden steps.
#
# This whole folder is GENERIC Ubuntu hardening. It knows nothing about steward —
# no steward user, no record, no Podman. It can be run on its own; steward just
# carries it (embedded) and can invoke it as an optional first step.

# Tunables — sane defaults, override via env.
SSH_PORT="${SSH_PORT:-22}"
FAIL2BAN_BAN_TIME="${FAIL2BAN_BAN_TIME:-1h}"
FAIL2BAN_FIND_TIME="${FAIL2BAN_FIND_TIME:-10m}"
FAIL2BAN_MAX_RETRY="${FAIL2BAN_MAX_RETRY:-5}"
UNATTENDED_REBOOT="${UNATTENDED_REBOOT:-true}"
UNATTENDED_REBOOT_TIME="${UNATTENDED_REBOOT_TIME:-04:00}"
UNATTENDED_RANDOM_SLEEP="${UNATTENDED_RANDOM_SLEEP:-1800}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_RED='\033[0;31m'; C_RESET='\033[0m'
info() { printf '  %s\n' "$*"; }
ok()   { printf "  ${C_GREEN}OK${C_RESET}   %s\n" "$*"; }
warn() { printf "  ${C_YELLOW}!${C_RESET}    %s\n" "$*"; }
fail() { printf "  ${C_RED}FAIL${C_RESET} %s\n" "$*" >&2; }

require_root() { [ "$(id -u)" -eq 0 ] || { fail "must run as root"; exit 1; }; }

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# wait_for_apt blocks until the dpkg/apt locks are free, or times out.
wait_for_apt() {
  local timeout="${1:-120}" waited=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    [ "$waited" -ge "$timeout" ] && return 1
    sleep 2; waited=$((waited + 2))
  done
  return 0
}
