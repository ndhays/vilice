#!/usr/bin/env bash
# A swap file, if none exists. Small reliability cushion against OOM on small boxes.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

if swapon --show | grep -q .; then
  ok "swap already present"
  exit 0
fi

SWAPFILE="/swapfile"
info "creating $SWAP_SIZE swap at $SWAPFILE"
if ! fallocate -l "$SWAP_SIZE" "$SWAPFILE" 2>/dev/null; then
  # fallocate can be unreliable on some filesystems; fall back to dd.
  mb=$(numfmt --from=iec "$SWAP_SIZE" | awk '{print int($1/1048576)}')
  dd if=/dev/zero of="$SWAPFILE" bs=1M count="$mb" status=none
fi
chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE" >/dev/null
swapon "$SWAPFILE"
grep -q "^$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
ok "swap active ($SWAP_SIZE)"
