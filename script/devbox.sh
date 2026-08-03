#!/usr/bin/env bash
# Tier-2 dev box: point Steward setup at a Linux box you already have (a spare
# machine, a homelab VM, a VPS) so local Steward Console can drive a real box over scoped
# SSH — the realistic dev loop (real sshd, Podman, Caddy, record). Mirrors production:
# Steward Console runs on your machine and reaches the box as the `steward` user.
#
#   script/devbox.sh up --ssh devbox      install steward, prepare, authorize a dev key
#   script/devbox.sh info --ssh devbox    print connection details + Steward Console registration
#   script/devbox.sh ssh status --ssh devbox   run a steward command over the scoped key
#   script/devbox.sh push --ssh devbox    rebuild the linux binary and reinstall it
#   script/devbox.sh harden --ssh devbox  run OS hardening on the box (opt-in)
#   script/devbox.sh deauth --ssh devbox  revoke the dev key (leaves the box intact)
#
# Name the box one of two ways:
#   --ssh <alias>   an ssh-config Host (supplies hostname, user, port, IdentityFile), or
#   DEVBOX_HOST=<ip> [DEVBOX_ADMIN=root] [DEVBOX_ADMIN_KEY=~/.ssh/key] [DEVBOX_PORT=22]
# Either way the admin login must be sudo-capable; `prepare` creates the unprivileged
# `steward` account that Steward Console then reaches over the scoped key. Other config:
# DEVBOX_SCOPE, DEVBOX_CLIENT, DEVBOX_KEY.
set -euo pipefail

HOST="${DEVBOX_HOST:-}"
ADMIN="${DEVBOX_ADMIN:-root}"
ADMIN_KEY="${DEVBOX_ADMIN_KEY:-}"
PORT="${DEVBOX_PORT:-22}"
ALIAS="${DEVBOX_SSH:-}"
SCOPE="${DEVBOX_SCOPE:-operate}"
CLIENT="${DEVBOX_CLIENT:-console-dev}"
KEY="${DEVBOX_KEY:-$HOME/.steward-devbox/id_ed25519}"
KNOWN_HOSTS="$(dirname "$KEY")/known_hosts"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/steward/bin/steward-linux-amd64"

say()  { printf '\n\033[1m• %s\033[0m\n' "$*"; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing '$1' — install it first"; }

# --ssh <alias> may appear anywhere on the line; everything else is positional.
pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ssh) shift; ALIAS="${1:-}"; [ -n "$ALIAS" ] || die "--ssh needs an alias" ;;
    *)     pos+=("$1") ;;
  esac
  shift
done
set -- ${pos[@]+"${pos[@]}"}

kh=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" -o ConnectTimeout=10)

# How to reach the box as the privileged (sudo) admin — an ssh alias, or user@host.
if [ -n "$ALIAS" ]; then
  admin_target="$ALIAS";        admin_opts=("${kh[@]}")
  scp_target="$ALIAS";          scp_opts=("${kh[@]}")
else
  admin_target="$ADMIN@$HOST";  admin_opts=(-p "$PORT" "${kh[@]}")
  scp_target="$ADMIN@$HOST";    scp_opts=(-P "$PORT" "${kh[@]}")
  if [ -n "$ADMIN_KEY" ]; then
    admin_opts+=(-i "$ADMIN_KEY" -o IdentitiesOnly=yes)
    scp_opts+=(-i "$ADMIN_KEY" -o IdentitiesOnly=yes)
  fi
fi

admin()  { ssh -tt "${admin_opts[@]}" "$admin_target" "$@"; }
# Reach the box exactly as Steward Console will — as `steward`, with only the dev key.
scoped() { ssh -i "$KEY" -o IdentitiesOnly=yes -p "$PORT" "${kh[@]}" "steward@$HOST" "$@"; }

# Resolve the real hostname + port (from the alias or user@host) for the scoped
# connection and the Machine registration. Also the presence check for "is a box named".
require_box() {
  { [ -n "$ALIAS" ] || [ -n "$HOST" ]; } || die "name a box: --ssh <alias> or DEVBOX_HOST=<ip>"
  mkdir -p "$(dirname "$KNOWN_HOSTS")"   # so ssh can persist the box's host key on first connect
  local g; g="$(ssh -G "${admin_opts[@]}" "$admin_target" 2>/dev/null)" \
    || die "could not resolve '${ALIAS:-$admin_target}'"
  HOST="$(awk '$1=="hostname"{print $2; exit}' <<<"$g")"
  PORT="$(awk '$1=="port"{print $2; exit}' <<<"$g")"
  [ -n "$HOST" ] || die "no hostname resolved for '${ALIAS:-$admin_target}'"
}

ensure_key() {
  if [ ! -f "$KEY" ]; then
    say "generating dev keypair at $KEY"
    mkdir -p "$(dirname "$KEY")"
    ssh-keygen -t ed25519 -N "" -C "$CLIENT" -f "$KEY" >/dev/null
  fi
}

build_binary() {
  say "building steward (linux/amd64)"
  make -C "$ROOT" build-linux >/dev/null
  [ -f "$BIN" ] || die "expected binary at $BIN"
}

install_binary() {
  say "installing steward on $HOST"
  scp "${scp_opts[@]}" "$BIN" "$scp_target:/tmp/steward"
  admin "sudo install -m 0755 /tmp/steward /usr/local/bin/steward && steward version"
}

cmd_up() {
  local harden=false
  [ "${1:-}" = "--harden" ] && harden=true
  need ssh; need scp; need make; need ssh-keygen
  require_box

  build_binary
  install_binary
  $harden && { say "hardening the box"; admin "sudo steward harden"; }

  say "preparing the box (sudo steward prepare --yes)"
  admin "sudo steward prepare --yes"

  ensure_key
  say "authorizing the dev key as '$CLIENT' at scope '$SCOPE'"
  admin "sudo -u steward steward authorize '$(cat "$KEY.pub")' --client '$CLIENT' --scope '$SCOPE'"

  self_test
  cmd_info
}

# Prove the whole scoped-SSH path end to end, from the host, exactly as Steward Console will.
self_test() {
  say "self-test: ssh steward@$HOST status --json"
  if scoped "status --json"; then
    printf '\033[32m  scoped SSH works — Steward Console can drive this box.\033[0m\n'
  else
    die "self-test failed — the scoped key could not reach steward on $HOST"
  fi
}

cmd_info() {
  require_box
  cat <<EOF

────────────────────────────────────────────────────────
  Dev box: $HOST  (port $PORT)
────────────────────────────────────────────────────────
  ssh user:   steward
  scope:      $SCOPE
  key:        $KEY

  Register it in Steward Console (bin/rails runner):

    Machine.create!(
      name:            "devbox",
      ssh_host:        "$HOST",
      ssh_port:        $PORT,
      ssh_user:        "steward",
      scope:           "$SCOPE",
      ssh_private_key: File.read("$KEY")
    )

  Or poke it directly:   script/devbox.sh ssh status${ALIAS:+ --ssh $ALIAS}
EOF
}

cmd_ssh() {
  [ $# -gt 0 ] || die "usage: devbox.sh ssh <steward-command>   (e.g. ssh status)"
  require_box
  scoped "$*"
}

cmd_push() {
  need ssh; need scp; need make
  require_box
  build_binary
  install_binary
  say "pushed — re-run any deploy/lifecycle to exercise the new binary"
}

cmd_harden() {
  require_box
  say "hardening $HOST (sudo steward harden)"
  admin "sudo steward harden"
}

cmd_deauth() {
  require_box
  say "revoking '$CLIENT' on $HOST"
  admin "sudo -u steward steward revoke '$CLIENT'"
  rm -f "$KNOWN_HOSTS"
}

case "${1:-}" in
  up)     shift; cmd_up "$@" ;;
  info)   cmd_info ;;
  ssh)    shift; cmd_ssh "$@" ;;
  push)   cmd_push ;;
  harden) cmd_harden ;;
  deauth) cmd_deauth ;;
  *)      grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'; exit 1 ;;
esac
