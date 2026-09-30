#!/usr/bin/env bash
# Builds the complete, Studio-ready place file:
#   1. rojo build  -> build/LastFlight.rojo.rbxl  (all scripts, no world yet)
#   2. bake        -> LastFlight.rbxl             (runs the game's map builders + Net.Setup and
#                                                  saves the airplane, lobby, spawn and remotes)
#   3. verify      -> fails unless the expected game content is inside LastFlight.rbxl
# Requires rojo (7.4+) and lune on PATH or in tools/.cache/bin.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/.cache/bin:$PATH"
OUT="${1:-LastFlight.rbxl}"
mkdir -p build
rojo build default.project.json -o build/LastFlight.rojo.rbxl
lune run tools/bake-place build/LastFlight.rojo.rbxl "$OUT"
lune run tools/verify-place "$OUT"
