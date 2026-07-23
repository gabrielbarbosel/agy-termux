#!/usr/bin/env sh
# agy-termux wrapper — Runs Antigravity CLI on Android/Termux via glibc.

BASE="$HOME/.local/share/agy-termux"
USR="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC="$USR/glibc/lib"

unset LD_PRELOAD LD_LIBRARY_PATH
export GODEBUG=netdns=cgo
export SSL_CERT_FILE="$USR/etc/tls/cert.pem"

# Android has no display server; let OAuth flows open the phone's browser.
export BROWSER="${BROWSER:-$USR/bin/termux-open-url}"

# Prevent native auto-update from replacing the patched binary.
export AGY_CLI_DISABLE_AUTO_UPDATE=true

# Termux glibc reads its config from $PREFIX/glibc/etc (not /etc) and ships
# resolv.conf/hosts as symlinks into $PREFIX/etc — the files dns-heal below
# maintains. Recreate the symlinks if a glibc update ever drops them.
[ -e "$USR/glibc/etc/resolv.conf" ] || ln -sfn "$USR/etc/resolv.conf" "$USR/glibc/etc/resolv.conf" 2>/dev/null || true
[ -e "$USR/glibc/etc/hosts" ] || ln -sfn "$USR/etc/hosts" "$USR/glibc/etc/hosts" 2>/dev/null || true

# agy is a Go binary running under glibc (netdns=cgo): every lookup goes
# through $PREFIX/etc/{resolv.conf,hosts}. If resolv.conf rots (e.g. a lone
# `nameserver 127.0.0.1`), token refresh dies in a loop with "Temporary
# failure in name resolution" and the CLI crashes. Heal it on every start
# and pin the Google endpoints with live answers (DoH fallback when port 53
# is blocked by Private DNS).
if command -v node >/dev/null 2>&1; then
  node "$BASE/adapter/dns-heal.js" "$USR/etc/hosts" "$USR/etc/resolv.conf" \
    oauth2.googleapis.com accounts.google.com www.googleapis.com \
    play.googleapis.com cloudcode-pa.googleapis.com \
    daily-cloudcode-pa.googleapis.com \
    2>/dev/null || true
fi

# Route `agy update` through our safe updater.
case "${1:-}" in
  update) exec bash "$BASE/adapter/update.sh" ;;
esac

exec "$GLIBC/ld-linux-aarch64.so.1" \
  --library-path "$BASE/lib:$GLIBC" \
  "$BASE/bin/agy.patched" "$@"
