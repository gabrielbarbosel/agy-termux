#!/usr/bin/env bash
# agy-termux update — Downloads, patches, and swaps the AGY binary.
set -euo pipefail

BASE="$HOME/.local/share/agy-termux"
GLIBC="${PREFIX:-/data/data/com.termux/files/usr}/glibc/lib"
PATCHED="$BASE/bin/agy.patched"
OFFICIAL="$BASE/bin/agy.official"
STAGING="$HOME/.cache/agy-termux/staging"
MANIFEST="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_arm64.json"

die() { echo "✗ $*" >&2; exit 1; }

run_patched() {
  unset LD_PRELOAD LD_LIBRARY_PATH 2>/dev/null || true
  GODEBUG=netdns=cgo \
  SSL_CERT_FILE="${PREFIX:-/data/data/com.termux/files/usr}/etc/tls/cert.pem" \
    "$GLIBC/ld-linux-aarch64.so.1" --library-path "$BASE/lib:$GLIBC" \
    "$PATCHED" "$@" 2>/dev/null
}

# parse_json prints the first string value of the given key in a JSON blob.
parse_json() { echo "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1; }

rollback() {
  [ -f "$PATCHED.bak" ] && mv "$PATCHED.bak" "$PATCHED" && echo "✓ Rolled back to v$CURRENT"
}

cleanup() { rm -rf "$STAGING" 2>/dev/null || true; }
trap cleanup EXIT

# Current version
CURRENT=$(run_patched --version || echo "unknown")

# Fetch manifest
echo "⠋ Checking for updates..."
manifest=$(curl -fsSL "$MANIFEST") || die "Cannot reach release server."
LATEST=$(parse_json "$manifest" "version")
URL=$(parse_json "$manifest" "url")
SHA512=$(parse_json "$manifest" "sha512")
[ -n "$URL" ] && [ -n "$SHA512" ] || die "Invalid release manifest."

# Already current?
if [ "$CURRENT" = "$LATEST" ]; then
  echo "✓ Antigravity CLI is already up to date (v$CURRENT)"
  exit 0
fi

echo "  v$CURRENT → v$LATEST"
echo "⠋ Downloading..."

# Download and verify
mkdir -p "$STAGING"
case "$URL" in *.tar.gz*) dl="$STAGING/agy.tar.gz" ;; *) dl="$STAGING/agy" ;; esac
curl -fsSL -o "$dl" "$URL" || die "Download failed."
actual=$(sha512sum "$dl" | cut -d' ' -f1)
[ "$actual" = "$SHA512" ] || die "Checksum mismatch — aborting."
echo "✓ Downloaded and verified."

# Extract tarball if needed
if [ "$dl" != "$STAGING/agy" ]; then
  tar -xzf "$dl" -C "$STAGING" 2>/dev/null || die "Extraction failed."
  bin=$(find "$STAGING" -type f \( -name 'antigravity' -o -name 'agy' \) ! -name '*.tar.gz' | head -1)
  [ -f "${bin:-}" ] || die "Binary not found in archive."
else
  bin="$dl"
fi

# Backup, patch, verify
[ -f "$PATCHED" ] && cp "$PATCHED" "$PATCHED.bak"
cp "$bin" "$OFFICIAL" && chmod +x "$OFFICIAL"

echo "⠋ Patching..."
if ! "$BASE/adapter/patch" "$OFFICIAL" "$PATCHED"; then
  echo "✗ Patch failed."; rollback; exit 1
fi
chmod +x "$PATCHED"

NEW=$(run_patched --version || echo "")
if [ -z "$NEW" ]; then
  echo "✗ Binary verification failed."; rollback; exit 1
fi

echo "✓ Updated: v$CURRENT → v$NEW"
