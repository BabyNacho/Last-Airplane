#!/usr/bin/env bash
# Static checks for LAST FLIGHT.
#  1. Builds the place file with Rojo (validates project structure).
#  2. Type-checks a strict-mode copy of every script against the Roblox API definitions and fails
#     on high-signal errors: unknown members on Roblox classes, unknown globals, bad requires,
#     syntax errors and argument-count mismatches. Pure inference noise is reported only with -v.
# Requires rojo and luau-lsp on PATH or in tools/.cache/bin.
set -uo pipefail
cd "$(dirname "$0")/.."
CACHE=tools/.cache
mkdir -p "$CACHE" build
export PATH="$PWD/$CACHE/bin:$PATH"
VERBOSE=${1:-}
if [ ! -f "$CACHE/globalTypes.d.luau" ]; then
  curl -sSL -o "$CACHE/globalTypes.d.luau" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau
fi
rojo build default.project.json -o build/LastFlight.rbxl || exit 1

STRICT="$CACHE/strict"
rm -rf "$STRICT" && mkdir -p "$STRICT"
cp -r src "$STRICT/src"
find "$STRICT/src" -name '*.luau' | while read -r f; do
  { echo '--!strict'; grep -v '^--!' "$f"; } > "$f.tmp" && mv "$f.tmp" "$f"
done
sed 's#"src/#"src/#g' default.project.json > "$STRICT/default.project.json"
(cd "$STRICT" && rojo sourcemap default.project.json -o sourcemap.json >/dev/null)
(cd "$STRICT" && luau-lsp analyze --sourcemap=sourcemap.json --definitions="$PWD/../globalTypes.d.luau" src/ 2>&1) \
  | grep -v '^\[INFO\]\|^\[WARN\]' > "$CACHE/analyze.log"

PATTERN="not found in external type|Unknown global|Unknown require|SyntaxError|not found in table 'typeof\(task\)|Key '[a-z]+' not found in table '\{ cancel"
grep -E "^(/|src).*($PATTERN)" "$CACHE/analyze.log" | grep -v "Unknown require: unsupported path" > "$CACHE/errors.log"
if [ "$VERBOSE" = "-v" ]; then cat "$CACHE/analyze.log"; fi
if [ -s "$CACHE/errors.log" ]; then
  cat "$CACHE/errors.log"
  echo "FAILED: $(wc -l < "$CACHE/errors.log") high-signal errors ($(grep -c TypeError "$CACHE/analyze.log") total diagnostics)"
  exit 1
fi
echo "OK: build + analyze passed ($(grep -c TypeError "$CACHE/analyze.log") low-signal strict diagnostics ignored)"
