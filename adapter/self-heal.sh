#!/usr/bin/env sh
# agy-termux self-heal — Re-patches if an official update overwrites the wrapper.

BASE="$HOME/.local/share/agy-termux"
GLIBC="${PREFIX:-/data/data/com.termux/files/usr}/glibc/lib"
WRAPPER="$HOME/.local/bin/agy"

# Only act if the wrapper was replaced by a raw ELF binary.
ELF_MAGIC=$(printf '\177ELF')
[ -f "$WRAPPER" ] && [ "$(head -c 4 "$WRAPPER" 2>/dev/null)" = "$ELF_MAGIC" ] || exit 0

echo "[agy-termux] Official binary detected — re-patching..."

mkdir -p "$BASE/bin" "$BASE/lib"
[ -f "$BASE/bin/agy.patched" ] && cp "$BASE/bin/agy.patched" "$BASE/bin/agy.patched.bak"
mv "$WRAPPER" "$BASE/bin/agy.official"

ln -sfn "$GLIBC/libc.so.6" "$BASE/lib/libc.so"
ln -sfn "$GLIBC/libc.so.6" "$BASE/lib/libc.so.6"

if "$BASE/adapter/patch" "$BASE/bin/agy.official" "$BASE/bin/agy.patched"; then
  echo "✓ Patch applied."
else
  echo "✗ Patch failed."
  if [ -f "$BASE/bin/agy.patched.bak" ]; then
    mv "$BASE/bin/agy.patched.bak" "$BASE/bin/agy.patched"
    echo "✓ Rolled back to previous version."
  else
    echo "✗ No backup — run: bash $BASE/adapter/update.sh"
  fi
fi

sed "1s|#!/usr/bin/env sh|#!${PREFIX:-/data/data/com.termux/files/usr}/bin/sh|" \
  "$BASE/adapter/wrapper.sh" > "$WRAPPER"
chmod +x "$WRAPPER"
echo "✓ Ready."
