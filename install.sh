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
# Where to get the public key. Codeberg — deliberately a different provider from
# the release host, so no single compromised account or server hands you both a
# matching key and binary. An attacker needs Codeberg *and* agoraforge.org, or the
# signature does not check out and this script refuses.
#
# Codeberg rather than the self-hosted forge: git.agoraforge.org and
# steward.agoraforge.org are different origins, but one DNS zone and one Cloudflare
# account sit above both, and that is a single credential that could re-point them
# together. See decisions/the-core-is-handwritten.md.
#
# The repo must be PUBLICLY readable: this is an unauthenticated fetch running on
# a stranger's box, so a private repo 404s here and no install can verify.
# Override with a local file via PUBKEY_FILE (also the way out if Codeberg is down —
# a failed key fetch fails closed, which is safe but stops the install).
PUBKEY_URL="${PUBKEY_URL:-https://codeberg.org/agoraforge/steward/raw/branch/main/steward/release-key.pub}"
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
    echo "steward publishes linux/amd64 and linux/arm64." >&2
    exit 1
    ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

base="$RELEASE_HOST/steward/$VERSION/steward-linux-$ARCH.tar.gz"
echo "• downloading steward $VERSION (linux/$ARCH)"
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
