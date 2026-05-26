#!/usr/bin/env bash
#
# run-omp-server-wine.sh — run the Windows open.mp server under CrossOver.
#
# macOS has no native open.mp server, and open.mp ships only a 32-bit Windows
# server, so the Server Launcher runs omp-server.exe through CrossOver in a
# dedicated 32-bit bottle (separate from qawno's compiler bottle).
#
# The launcher creates the OpenMPServer bottle and invokes this script with the
# server folder as the working directory (and OMP_SERVER_DIR set). Layout:
#     <server-dir>/omp-server.exe       (Windows open.mp server, 32-bit)
#     <server-dir>/components/*.dll      (Windows components)
#     <server-dir>/config.json, gamemodes/, filterscripts/, ...
set -euo pipefail

CX_ROOT="${CX_ROOT:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
export CX_ROOT
WINE="${WINE:-$CX_ROOT/bin/wine}"
BOTTLE="${OMP_WINE_BOTTLE:-OpenMPServer}"
export WINEDEBUG="${WINEDEBUG:--all}"

SERVER_DIR="${OMP_SERVER_DIR:-$(pwd)}"

if [[ ! -x "$WINE" ]]; then
  echo "CrossOver Wine not found at: $WINE" >&2
  echo "Install CrossOver, or set WINE=/path/to/wine" >&2
  exit 1
fi
if [[ ! -f "$SERVER_DIR/omp-server.exe" ]]; then
  echo "omp-server.exe not found in: $SERVER_DIR" >&2
  echo "Put the Windows open.mp server (open.mp-win-x86.zip) here." >&2
  exit 1
fi

cd "$SERVER_DIR"
exec "$WINE" --bottle "$BOTTLE" "$SERVER_DIR/omp-server.exe" "$@"
