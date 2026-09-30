#!/usr/bin/env bash
# Builds the place and runs the headless server simulation (every disaster, multiplayer,
# leave mid-round, wipe, DataStore outage, receipts, shop). Requires rojo + lune.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/tools/.cache/bin:$PATH"
mkdir -p build
rojo build default.project.json -o build/LastFlight.rbxl >/dev/null
# the complete (baked) place is exercised by the "Baked place" scenario
./tools/build-place.sh >/dev/null
lune run tests/sim/run "$@"
