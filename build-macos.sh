#!/usr/bin/env bash
#
# Build the open.mp Server Launcher as a native macOS .app bundle, then ship
# the bundle into ./dist.
#
# Requires Homebrew with Qt and cmake:  brew install qt cmake
#
# Usage:
#   ./build-macos.sh            # configure + build  -> build/, then dist/
#   ./build-macos.sh --deploy   # also bundle Qt frameworks (standalone .app)
#   ./build-macos.sh --clean    # wipe the build directory first
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"

DEPLOY=0
for arg in "$@"; do
  case "$arg" in
    --deploy) DEPLOY=1 ;;
    --clean)  rm -rf "$BUILD" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

QT_PREFIX="$(brew --prefix qt 2>/dev/null || true)"
if [[ -z "$QT_PREFIX" ]]; then
  echo "Qt not found via Homebrew. Run: brew install qt cmake" >&2
  exit 1
fi

# Load local env vars if a .env file exists at the project root.
# This is only for the current shell; it does not commit secrets into the repo.
if [[ -f "$ROOT/.env" ]]; then
  echo "Loading environment from $ROOT/.env"
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/.env"
  set +a
fi

if [[ -f "$BUILD/CMakeCache.txt" ]]; then
  old_source=$(grep -m1 '^CMAKE_HOME_DIRECTORY:INTERNAL=' "$BUILD/CMakeCache.txt" | cut -d'=' -f2-)
  if [[ -n "$old_source" && "$old_source" != "$ROOT" ]]; then
    echo "Detected stale build directory from: $old_source"
    echo "Cleaning $BUILD to avoid CMake cache conflicts."
    rm -rf "$BUILD"
  fi
fi

cmake -S "$ROOT" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$QT_PREFIX"
cmake --build "$BUILD" --parallel "$(sysctl -n hw.ncpu)"

APP="$BUILD/open.mp Server Launcher.app"

if [[ "$DEPLOY" -eq 1 ]]; then
  echo "Bundling Qt frameworks ..."
  "$QT_PREFIX/bin/macdeployqt" "$APP"
fi

# Always ship the built .app into ./dist.
mkdir -p "$DIST"
rm -rf "$DIST/$(basename "$APP")"
cp -R "$APP" "$DIST/"

echo
echo "Built:   $APP"
echo "Shipped: $DIST/$(basename "$APP")"
echo "Run it with:  open \"$DIST/$(basename "$APP")\""
