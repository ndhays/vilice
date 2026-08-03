#!/usr/bin/env bash
# Download, verify (ed25519), and install the steward binary.
#
#   curl -fsSL https://steward.agoraforge.org/install.sh | sudo bash -s -- <version>
#
# Or locally, against a file:// release dir and the committed public key:
#   RELEASE_HOST="file://$PWD/release/published" PUBKEY_FILE=steward/release-key.pub \
#     INSTALL_PATH=/tmp/steward sudo -E bash install.sh <version>
#
# The signature is checked against the public key BEFORE the binary is installed.
set -euo pipefail

VERSION="${1:-${VERSION:-}}"
# One site, releases under /releases/.
RELEASE_HOST="${RELEASE_HOST:-https://steward.agoraforge.org/releases}"
INSTALL_PATH="${INSTALL_PATH:-/usr/local/bin/steward}"
# Where to get the public key. By default fetch it from the source repo (a
# different host than the release server, so no single server hands you both a
# matching key and binary). Override with a local file via PUBKEY_FILE.
PUBKEY_URL="${PUBKEY_URL:-https://raw.githubusercontent.com/ndhays/steward/main/steward/release-key.pub}"
PUBKEY_FILE="${PUBKEY_FILE:-}"

if [ -z "$VERSION" ]; then
  echo "usage: install.sh <version>   (e.g. install.sh 1.2.3)" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

base="$RELEASE_HOST/steward/$VERSION/steward-linux-amd64.tar.gz"
echo "• downloading steward $VERSION"
curl -fsSL "$base"      -o "$TMP/steward.tar.gz"
curl -fsSL "$base.sig"  -o "$TMP/steward.tar.gz.sig"

if [ -n "$PUBKEY_FILE" ]; then
  cp "$PUBKEY_FILE" "$TMP/key.pub"
else
  curl -fsSL "$PUBKEY_URL" -o "$TMP/key.pub"
fi

echo "• verifying signature"
if ! openssl pkeyutl -verify -rawin -pubin -inkey "$TMP/key.pub" \
       -in "$TMP/steward.tar.gz" -sigfile "$TMP/steward.tar.gz.sig" >/dev/null 2>&1; then
  echo "SIGNATURE VERIFICATION FAILED — refusing to install" >&2
  exit 1
fi
echo "  signature ok"

tar -xzf "$TMP/steward.tar.gz" -C "$TMP"
install -m 0755 "$TMP/steward" "$INSTALL_PATH"
# The man page rides in the same signed tarball (older releases don't have it).
if [ -f "$TMP/steward.1" ]; then
  install -D -m 0644 "$TMP/steward.1" /usr/local/share/man/man1/steward.1
fi
echo "• installed: $("$INSTALL_PATH" version)  →  $INSTALL_PATH"
