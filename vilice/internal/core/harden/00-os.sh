#!/usr/bin/env bash
# Confirm we're on Debian 13, and stop otherwise. A hard check, not a warning: the
# steps after this make security claims (30-unattended says which updates install
# themselves) that are true only on the OS they were written for. On a close relative
# they could apply cleanly and claim a posture the box does not have.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "Detected: ${PRETTY_NAME:-unknown}"
fi
if [ "${ID:-}" != "debian" ] || [ "${VERSION_ID:-}" != "13" ]; then
  fail "These steps are for Debian 13 only; this box is '${PRETTY_NAME:-unknown}'"
  exit 1
fi
ok "Debian 13"
