#!/usr/bin/env bash
# What root schedules, and how sshd is configured, readable by root only. Nothing on the
# box reads these as anyone else (cron and sshd run as root); a local user who could
# read them would learn what runs as root and when.
#
# Set with dpkg-statoverride, so a package upgrade puts the mode back rather than its own.
#
# Not /etc/at.deny: Debian ships it 640 root:daemon because `at` reads it through the
# daemon group. 600 would break `at` and protect nothing more.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

for entry in "${HARDEN_ROOT_ONLY[@]}"; do
  mode="${entry%% *}" path="${entry#* }"
  [ -e "$path" ] || continue
  current="$(dpkg-statoverride --list "$path" 2>/dev/null || true)"
  if [ "$current" != "root root $mode $path" ]; then
    if [ -n "$current" ]; then dpkg-statoverride --remove "$path"; fi
    dpkg-statoverride --update --add root root "$mode" "$path"
    ok "$path is $mode root:root"
  else
    # The override only acts on package upgrades; put back a mode changed by hand.
    chown root:root "$path"; chmod "$mode" "$path"
    ok "$path already $mode"
  fi
done
