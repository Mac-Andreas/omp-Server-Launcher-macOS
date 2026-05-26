#!/usr/bin/env bash
# Build the Swift launcher as a native macOS .app bundle into ./dist.
#
#   scripts/build-app.sh            # release build -> dist/<App>.app
#   scripts/build-app.sh --debug    # debug build (faster, no optimisation)
#
# No secrets are read or embedded — telemetry uses the public Edge Function URL.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="open.mp Server Launcher"
BIN_NAME="ServerLauncher"
BUNDLE_ID="org.openmultiplayer.serverlauncher"
VERSION="1.0.0"

CONFIG="release"
SWIFT_FLAGS=(-c release)
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"; SWIFT_FLAGS=()
fi

echo "==> swift build ($CONFIG)"
swift build "${SWIFT_FLAGS[@]}"

BIN_PATH="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
APP="dist/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# Executable
cp "$BIN_PATH/$BIN_NAME" "$MACOS/$BIN_NAME"

# SPM resource bundle (contains LICENSE, icon, wine wrapper). Copy the whole
# bundle so Bundle.module works, AND copy the raw files into Resources so
# Bundle.main lookups also resolve in the shipped app.
if [[ -d "$BIN_PATH/${BIN_NAME}_${BIN_NAME}.bundle" ]]; then
  cp -R "$BIN_PATH/${BIN_NAME}_${BIN_NAME}.bundle" "$RES/"
fi
cp "Sources/ServerLauncher/Resources/run-omp-server-wine.sh" "$RES/"
cp "Sources/ServerLauncher/Resources/LICENSE.txt" "$RES/"
chmod +x "$RES/run-omp-server-wine.sh"

# Wine wrapper also next to the executable (ServerController checks Bundle.main
# Resources first, but keep a MacOS-dir copy as the original C++ app did).
cp "Sources/ServerLauncher/Resources/run-omp-server-wine.sh" "$MACOS/"
chmod +x "$MACOS/run-omp-server-wine.sh"

# Icon -> .icns
echo "==> generating AppIcon.icns"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC_ICON="../assets/icon_1024x1024.png"
if [[ -f "$SRC_ICON" ]]; then
  for sz in 16 32 64 128 256 512; do
    sips -z $sz $sz "$SRC_ICON" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) "$SRC_ICON" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
else
  echo "   (no source icon at $SRC_ICON — skipping)"
fi

# Info.plist
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>        <string>$BIN_NAME</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>    <string>14.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSApplicationCategoryType</key> <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so Gatekeeper at least sees a signature (not notarized).
echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "   (codesign skipped)"

echo "==> done: $APP"
