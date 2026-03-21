#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FrostBar"
APP_BUNDLE_ID="com.frostbar.app"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/app/$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
DIST_DIR="$ROOT_DIR/dist"
PKG_DIR="$BUILD_DIR/package"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RW_DMG_PATH="$BUILD_DIR/$APP_NAME-rw.dmg"

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$PKG_DIR"

printf '\n[1/6] Running logic tests...\n'
mkdir -p "$BUILD_DIR/tests"
swiftc \
  "$ROOT_DIR/app-swift/Sources/App/VisibilityStore.swift" \
  "$ROOT_DIR/tests/visibility_store_test.swift" \
  -o "$BUILD_DIR/tests/visibility_store_test"
"$BUILD_DIR/tests/visibility_store_test"

printf '\n[2/6] Building app executable...\n'
mkdir -p "$BUILD_DIR/app"
swiftc \
  "$ROOT_DIR/app-swift/Sources/App/main.swift" \
  -o "$BUILD_DIR/app/$APP_NAME" \
  -framework AppKit

printf '\n[3/6] Assembling app bundle...\n'
mkdir -p "$BIN_DIR" "$RES_DIR"
mv "$BUILD_DIR/app/$APP_NAME" "$BIN_DIR/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>FrostBar.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>0.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -f "$ROOT_DIR/FrostBar.jpeg" ]]; then
  cp "$ROOT_DIR/FrostBar.jpeg" "$RES_DIR/FrostBar.jpeg"

  ICONSET_DIR="$BUILD_DIR/FrostBar.iconset"
  if [[ -d "$ICONSET_DIR" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$ROOT_DIR/delete"
    mv "$ICONSET_DIR" "$ROOT_DIR/delete/FrostBar-iconset-prev-$ts"
  fi
  mkdir -p "$ICONSET_DIR"

  sips -s format png -z 16 16 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -s format png -z 32 32 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -s format png -z 32 32 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -s format png -z 64 64 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -s format png -z 128 128 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -s format png -z 256 256 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -s format png -z 256 256 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -s format png -z 512 512 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -s format png -z 512 512 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -s format png -z 1024 1024 "$ROOT_DIR/FrostBar.jpeg" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$RES_DIR/FrostBar.icns"
fi

printf '\n[4/6] Signing app...\n'
codesign --force --deep --sign - "$APP_DIR"

printf '\n[5/6] Packaging dmg...\n'
if [[ -e "$PKG_DIR/$APP_NAME.app" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT_DIR/delete"
  mv "$PKG_DIR/$APP_NAME.app" "$ROOT_DIR/delete/$APP_NAME-app-prev-$ts.app"
fi
cp -R "$APP_DIR" "$PKG_DIR/$APP_NAME.app"
if [[ ! -L "$PKG_DIR/Applications" ]]; then
  ln -s /Applications "$PKG_DIR/Applications"
fi

if [[ -f "$DMG_PATH" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT_DIR/delete"
  mv "$DMG_PATH" "$ROOT_DIR/delete/$APP_NAME-prev-$ts.dmg"
fi

if [[ -f "$RW_DMG_PATH" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT_DIR/delete"
  mv "$RW_DMG_PATH" "$ROOT_DIR/delete/$APP_NAME-rw-prev-$ts.dmg"
fi

hdiutil create -volname "$APP_NAME" -srcfolder "$PKG_DIR" -ov -format UDRW "$RW_DMG_PATH" >/dev/null

MOUNT_POINT=$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen | awk '/\/Volumes\// { print $3; exit }')

osascript <<OSA >/dev/null
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 740, 470}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set text size of opts to 14
    set position of item "$APP_NAME.app" of container window to {170, 190}
    set position of item "Applications" of container window to {470, 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
OSA

hdiutil detach "$MOUNT_POINT" >/dev/null
hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -imagekey zlib-level=9 -o "$DIST_DIR/$APP_NAME" >/dev/null

printf '\n[6/6] Verifying package...\n'
TMP_MOUNT="$(mktemp -d /tmp/frostbar-mount.XXXXXX)"
hdiutil mount "$DMG_PATH" -mountpoint "$TMP_MOUNT" >/dev/null
[[ -d "$TMP_MOUNT/$APP_NAME.app" ]] || { echo "DMG verification failed: app missing"; exit 1; }
[[ -x "$TMP_MOUNT/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]] || { echo "DMG verification failed: executable missing"; exit 1; }
hdiutil unmount "$TMP_MOUNT" >/dev/null

ls -lh "$DMG_PATH"
stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$DMG_PATH"
echo "Done: build, test, package, and verification completed."
