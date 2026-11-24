#!/usr/bin/env bash
# Kernel settings, and network protocols the kernel may not load. The list is
# HARDEN_SYSCTLS in common.sh (check.sh reads the same one). What each is for:
#
#   ldisc_autoload=0, unprivileged_bpf_disabled=1, bpf_jit_harden=2
#                      close paths unprivileged code has used to reach kernel bugs
#   kptr_restrict=2    kernel addresses hidden, even from root's tools
#   protected_fifos=2  no writing to someone else's FIFO in a shared sticky directory
#   ptrace_scope=1     a process may trace only its own children
#   sysrq=0            no magic-SysRq keys; the provider's console can still reboot
#   log_martians=1     packets with impossible source addresses are logged
#   rp_filter=2        loose: drop packets from addresses no route leads back to. Not
#                      strict (1): a box on a private network as well as the public one
#                      can route asymmetrically, and strict would drop real traffic.
#   send_redirects=0   the box is not a router
#
# Not set: kernel.modules_disabled=1. It stops every module load after boot, and Podman,
# ufw and nftables load modules as they go.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

SYSCTL_FILE="/etc/sysctl.d/90-harden.conf"
DESIRED="# Generic harden policy: kernel settings. Written by harden; see 25-kernel.sh."
for kv in "${HARDEN_SYSCTLS[@]}"; do
  DESIRED+=$'\n'"${kv%%=*} = ${kv#*=}"
done
if [ -f "$SYSCTL_FILE" ] && diff -q <(echo "$DESIRED") "$SYSCTL_FILE" >/dev/null 2>&1; then
  ok "kernel settings already current"
else
  echo "$DESIRED" > "$SYSCTL_FILE"; chmod 644 "$SYSCTL_FILE"
  ok "wrote $SYSCTL_FILE"
fi
sysctl -q -p "$SYSCTL_FILE"
ok "kernel settings applied"

MODPROBE_FILE="/etc/modprobe.d/harden-protocols.conf"
DESIRED="# Generic harden policy: protocols nothing here uses may not be loaded."
for p in "${HARDEN_UNUSED_PROTOCOLS[@]}"; do
  DESIRED+=$'\n'"install $p /bin/false"$'\n'"blacklist $p"
done
if [ -f "$MODPROBE_FILE" ] && diff -q <(echo "$DESIRED") "$MODPROBE_FILE" >/dev/null 2>&1; then
  ok "unused protocols already blocked"
else
  echo "$DESIRED" > "$MODPROBE_FILE"; chmod 644 "$MODPROBE_FILE"
  ok "wrote $MODPROBE_FILE"
fi
# One already loaded stays until a reboot unless it can come out now.
for p in "${HARDEN_UNUSED_PROTOCOLS[@]}"; do
  if lsmod | grep -q "^$p "; then
    if modprobe -r "$p" 2>/dev/null; then ok "unloaded $p"; else warn "$p is in use; blocked from the next boot"; fi
  fi
done
