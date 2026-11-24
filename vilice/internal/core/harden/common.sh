#!/usr/bin/env bash
# Shared helpers and tunables for the harden steps.
#
# This whole folder is GENERIC Debian 13 hardening. It knows nothing about vilice —
# no _vilice user, no record, no Podman. It can be run on its own; vilice just
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

# Kernel settings 25-kernel.sh applies and check.sh verifies: one list, so they can't
# drift apart. The why for each is in 25-kernel.sh.
# shellcheck disable=SC2034 # read by 25-kernel.sh and check.sh
HARDEN_SYSCTLS=(
  "dev.tty.ldisc_autoload=0"
  "fs.protected_fifos=2"
  "kernel.kptr_restrict=2"
  "kernel.sysrq=0"
  "kernel.unprivileged_bpf_disabled=1"
  "kernel.yama.ptrace_scope=1"
  "net.core.bpf_jit_harden=2"
  "net.ipv4.conf.all.log_martians=1"
  "net.ipv4.conf.default.log_martians=1"
  "net.ipv4.conf.all.rp_filter=2"
  "net.ipv4.conf.default.rp_filter=2"
  "net.ipv4.conf.all.send_redirects=0"
  "net.ipv4.conf.default.send_redirects=0"
)
# Network protocols nothing on the box uses, whose modules the kernel would otherwise
# load on demand — from inside a rootless container too.
# shellcheck disable=SC2034 # read by 25-kernel.sh and check.sh
HARDEN_UNUSED_PROTOCOLS=(dccp sctp rds tipc)

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
