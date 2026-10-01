#!/usr/bin/env bash
# Confirm we're on a supported OS. Soft check: warn rather than hard-fail, so the
# steps can still be attempted (and read) on close relatives.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  info "Detected: ${PRETTY_NAME:-unknown}"
fi
if [ "${ID:-}" != "ubuntu" ]; then
  warn "These steps target Ubuntu; '${ID:-unknown}' may behave differently"
fi
ok "OS check done"
