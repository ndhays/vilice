#!/usr/bin/env bash
# Key-only SSH: no passwords; classic ssh.service. Root login is closed entirely
# (PermitRootLogin no) when some non-root account can already log in by key,
# otherwise kept key-only (prohibit-password) so a fresh box isn't locked out.
#
# Debian ships ssh.socket disabled; if someone enabled it, it would intercept the port
# and ignore the Port directive, so make sure the classic daemon is what listens.
# Refuses to disable passwords if no key-based login exists at all, to avoid locking
# everyone out.
#
# Algorithms: only modern ones, per ssh-audit. Key exchange is post-quantum hybrid or
# curve25519; ciphers are AES-GCM/CTR (no chacha20-poly1305, the Terrapin-exposed one,
# no CBC); MACs are encrypt-then-MAC only (no SHA-1, no encrypt-and-MAC); host keys are
# ed25519 or RSA signed with SHA-2 (no ECDSA, no ssh-rsa/SHA-1). Every client Vilice
# expects is a current OpenSSH. What a *user's* key may be (ecdsa included) is left
# alone: narrowing that could lock someone out.
set -euo pipefail
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$STEP_DIR/common.sh"
require_root

DROPIN="/etc/ssh/sshd_config.d/10-harden.conf"

# --- who can log in by key? (generic: this folder knows nothing about vilice) ---
# A key login is any authorized_keys file with at least one non-comment line.
has_keys() { [ -s "$1" ] && grep -qvE '^\s*(#|$)' "$1"; }

root_has_key=false
has_keys /root/.ssh/authorized_keys && root_has_key=true

# A non-root admin is any uid>=1000 user with a login shell and a key.
admin_user=""
while IFS=: read -r u _ uid _ _ home shell; do
  [ "$uid" -ge 1000 ] 2>/dev/null || continue
  [ "$uid" -eq 65534 ] && continue            # nobody
  case "$shell" in */nologin | */false | "") continue ;; esac
  if has_keys "$home/.ssh/authorized_keys"; then admin_user="$u"; break; fi
done < /etc/passwd

# Lockout safety: refuse to disable passwords unless *someone* can get in by key.
if [ "$root_has_key" != true ] && [ -z "$admin_user" ]; then
  fail "no key-based SSH login exists (root or otherwise) — refusing to disable password auth (lockout risk)"
  exit 1
fi

# Root-login policy (auto, when safe): if a non-root account can SSH in, root no
# longer needs SSH at all, so close it. Otherwise keep key-only root, to avoid lockout.
if [ -n "$admin_user" ]; then
  ROOT_LOGIN="no"
  ok "non-root SSH account '$admin_user' present — disabling root SSH login"
else
  ROOT_LOGIN="prohibit-password"
  ok "no non-root SSH account yet — keeping key-only root (PermitRootLogin prohibit-password)"
fi

# --- classic ssh.service, not socket activation ---
if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
  info "ssh.socket is enabled — switching to classic ssh.service"
  systemctl disable --now ssh.socket
  systemctl enable ssh.service
  ok "switched to classic ssh.service"
else
  ok "ssh.socket not active (classic daemon)"
fi

read -r -d '' CONF <<EOF || true
Port $SSH_PORT
PermitRootLogin $ROOT_LOGIN
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
KexAlgorithms mlkem768x25519-sha256,sntrup761x25519-sha512,sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,sk-ssh-ed25519@openssh.com,sk-ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-512-cert-v01@openssh.com,rsa-sha2-256,rsa-sha2-256-cert-v01@openssh.com
EOF

# The old drop-in is kept until the new one validates. A config sshd rejects must not
# stay on disk: the next restart or reboot would leave the box with no sshd at all.
OLD="" WROTE=false
if [ -f "$DROPIN" ] && diff -q <(echo "$CONF") "$DROPIN" >/dev/null 2>&1; then
  ok "sshd drop-in already current"
else
  if [ -f "$DROPIN" ]; then OLD="$(mktemp)"; cp -p "$DROPIN" "$OLD"; fi
  echo "$CONF" > "$DROPIN"
  chmod 644 "$DROPIN"
  WROTE=true
  ok "wrote $DROPIN"
fi

if ! sshd -t; then
  if [ "$WROTE" = true ]; then
    if [ -n "$OLD" ]; then mv "$OLD" "$DROPIN"; else rm -f "$DROPIN"; fi
    fail "sshd rejected the new config — put the previous one back, not reloading"
  else
    fail "sshd config invalid (not from this step) — not reloading"
  fi
  exit 1
fi
if [ -n "$OLD" ]; then rm -f "$OLD"; fi
# Reload (not restart) so the live session survives; restart only if not running.
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || systemctl restart ssh
ok "sshd hardened (key-only, no passwords; root login: $ROOT_LOGIN)"
