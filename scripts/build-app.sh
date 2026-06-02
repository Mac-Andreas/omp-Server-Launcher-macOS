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

# User-facing .app name (what Spotlight/Finder show). The backend identity is
# the bundle id + executable below, which stay technical.
APP_NAME="Open Multiplayer — Server Manager"
DISPLAY_NAME="Open Multiplayer — Server Manager"
# DMG / volume file name (short, file-system friendly).
DMG_NAME="omp-server-manager"
BIN_NAME="ServerLauncher"
BUNDLE_ID="org.openmultiplayer.servermanager"
VERSION="2.0.0"

CONFIG="release"
SWIFT_FLAGS=(-c release)
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"; SWIFT_FLAGS=()
fi

echo "==> swift build ($CONFIG)"
swift build ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}

# Start from a clean dist/ so it only ever holds this build's artifacts
# (the .app and the .dmg) — nothing else.
echo "==> cleaning dist/"
rm -rf dist
mkdir -p dist

BIN_PATH="$(swift build ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)"
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

# Icon -> .icns. Regenerate the 1024px master from the icon script (open.mp
# themed) so it stays in sync, then build the .iconset.
echo "==> generating AppIcon.icns"
SRC_ICON="assets/icon_1024x1024.png"
swift scripts/make-app-icon.swift "$SRC_ICON" >/dev/null 2>&1 || echo "   (icon generation skipped; using existing)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
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
  <key>CFBundleName</key>              <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>       <string>$DISPLAY_NAME</string>
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

# ---------------------------------------------------------------------------
# Package a drag-to-install .dmg with a styled background (arrow pointing the
# app at the Applications folder), a help README, and a custom window layout.
# ---------------------------------------------------------------------------
DMG="dist/$DMG_NAME-v$VERSION.dmg"
VOL="$DMG_NAME"
echo "==> building $DMG"

# 1. Render the background image (CoreGraphics via Swift).
BG="$(mktemp -d)/background.tiff"
swift scripts/make-dmg-background.swift "$BG" >/dev/null

# 2. Stage the DMG contents.
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg-readme.txt "$STAGE/Read Me.txt"
cp "$BG" "$STAGE/.background/background.tiff"

# 3. Create a writable image we can lay out, then convert to compressed RO.
RW="$(mktemp -d)/rw.dmg"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ \
  -format UDRW -ov "$RW" >/dev/null

# Mount at the default /Volumes location so Finder can address the disk by its
# volume name (a custom -mountpoint makes `disk "<name>"` unresolvable, -1728).
hdiutil attach "$RW" -nobrowse -noautoopen >/dev/null
MOUNT_DIR="/Volumes/$VOL"

# 4. Finder layout. Coordinates are AppleScript top-down on a 640x400 canvas
#    and MUST match make-dmg-background.swift:
#      Read Me icon  top-center   (320, 95)
#      app icon      middle-left  (160, 200)
#      Applications  middle-right (480, 200)
#    Window is sized exactly to the 640x400 background and chrome is hidden so
#    it reads as a fixed, non-scrolling install window.
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "   (Finder layout skipped)"
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    -- Top-left at (300,140); width 640, height 400 (+ ~23pt title bar).
    set the bounds of container window to {300, 140, 940, 563}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set text size of theViewOptions to 12
    -- Show the generic document icon for Read Me.txt, not a (huge) text preview.
    set shows icon preview of theViewOptions to false
    try
      set background picture of theViewOptions to file ".background:background.tiff" of disk "$VOL"
    on error
      set background picture of theViewOptions to file ".background:background.tiff"
    end try
    set position of item "Read Me.txt" of container window to {320, 95}
    set position of item "$APP_NAME.app" of container window to {160, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1

# 5. Compress to the final read-only image.
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null

rm -rf "$STAGE" "$MOUNT_DIR" "$RW"
echo "==> done: $DMG"
