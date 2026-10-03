#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Part of the MIT-licensed substrate (see vilice/LICENSE), not the AGPL repo root.
#
# Download, verify (ed25519), and install the vilice binary.
#
#   curl -fsSL https://get.vilice.org/install.sh | sudo bash -s -- <version>
#
# Or locally, against a file:// release dir and the committed public key:
#   RELEASE_HOST="file://$PWD/release/published" PUBKEY_FILE=vilice/release-key.pub \
#     INSTALL_PATH=/tmp/vilice sudo -E bash install.sh <version>
#
# The signature is checked against the public key BEFORE the binary is installed.
set -euo pipefail

VERSION="${1:-${VERSION:-}}"
# The installer host serves this script and the releases, and nothing else.
RELEASE_HOST="${RELEASE_HOST:-https://get.vilice.org/releases}"
INSTALL_PATH="${INSTALL_PATH:-/usr/local/bin/vilice}"
# Where to get the public key. Codeberg — deliberately a different provider from
# the release host, so no single compromised account or server hands you both a
# matching key and binary. An attacker needs Codeberg *and* get.vilice.org, or the
# signature does not check out and this script refuses.
#
# Not GitHub, where the source lives: the key is kept off the host that holds the
# code, too, so one compromised account cannot change both what a release is and the
# key that vouches for it. See decisions/the-name-is-vilice.md.
#
# The repo must be PUBLICLY readable: this is an unauthenticated fetch running on
# a stranger's box, so a private repo 404s here and no install can verify.
# Override with a local file via PUBKEY_FILE (also the way out if Codeberg is down —
# a failed key fetch fails closed, which is safe but stops the install).
PUBKEY_URL="${PUBKEY_URL:-https://codeberg.org/vilice/vilice/raw/branch/main/release-key.pub}"
PUBKEY_FILE="${PUBKEY_FILE:-}"

if [ -z "$VERSION" ]; then
  echo "usage: install.sh <version>   (e.g. install.sh 1.2.3)" >&2
  exit 1
fi

# Which build to fetch. Refused up front rather than defaulted: an installer that
# guesses amd64 downloads a real, correctly-signed binary that cannot execute, and
# the box only says so later, from the kernel, as "Exec format error" — which does
# not look like an install problem, so nobody looks here. Fail loud, before the
# download, naming what this machine is.
case "$(uname -m)" in
  x86_64 | amd64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    echo "vilice publishes linux/amd64 and linux/arm64." >&2
    exit 1
    ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

base="$RELEASE_HOST/vilice/$VERSION/vilice-linux-$ARCH.tar.gz"
echo "• downloading vilice $VERSION (linux/$ARCH)"
curl -fsSL "$base"      -o "$TMP/vilice.tar.gz"
curl -fsSL "$base.sig"  -o "$TMP/vilice.tar.gz.sig"

if [ -n "$PUBKEY_FILE" ]; then
  cp "$PUBKEY_FILE" "$TMP/key.pub"
else
  curl -fsSL "$PUBKEY_URL" -o "$TMP/key.pub"
fi

echo "• verifying signature"
if ! openssl pkeyutl -verify -rawin -pubin -inkey "$TMP/key.pub" \
       -in "$TMP/vilice.tar.gz" -sigfile "$TMP/vilice.tar.gz.sig" >/dev/null 2>&1; then
  echo "SIGNATURE VERIFICATION FAILED — refusing to install" >&2
  exit 1
fi
echo "  signature ok"

tar -xzf "$TMP/vilice.tar.gz" -C "$TMP"
install -m 0755 "$TMP/vilice" "$INSTALL_PATH"
# The man page rides in the same signed tarball (older releases don't have it).
if [ -f "$TMP/vilice.1" ]; then
  install -D -m 0644 "$TMP/vilice.1" /usr/local/share/man/man1/vilice.1
fi
echo "• installed: $("$INSTALL_PATH" version)  →  $INSTALL_PATH"

# Say what comes next, because installing is half of it. On a box that is already
# prepared this was an upgrade, and the new binary is on disk but not yet in force:
# every verb refuses a binary the box has not approved, until root runs prepare again.
# The role is printed only if it is one we know — this line suggests a root command,
# so it never echoes a file's contents back unchecked.
ROLE_FILE="${ROLE_FILE:-/var/lib/vilice/role}"
role=""
[ -r "$ROLE_FILE" ] && role="$(tr -d '[:space:]' < "$ROLE_FILE")"
case "$role" in
  host | balancer)
    echo "• next, to put it in force:  sudo vilice prepare $role"
    ;;
  *)
    echo "• next:  sudo vilice harden          (optional, and first)"
    echo "         sudo vilice prepare host    (or: balancer)"
    ;;
esac
