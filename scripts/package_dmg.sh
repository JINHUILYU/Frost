#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FrostBar"
APP_DIR="$ROOT_DIR/build/app/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/dmg-stage"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RW_DMG_PATH="$DIST_DIR/$APP_NAME-rw.dmg"
VERSION_FILE="$ROOT_DIR/build/version.txt"
DELETE_DIR="$ROOT_DIR/delete"

APP_VERSION="0.1.0"
if [[ -f "$VERSION_FILE" ]]; then
    APP_VERSION="$(cat "$VERSION_FILE")"
fi

mkdir -p "$DELETE_DIR"

# Keep dist clean: move old generated DMGs/symlinks to delete/ before creating new one.
if [[ -e "$DIST_DIR/$APP_NAME-latest.dmg" ]]; then
    mv -f "$DIST_DIR/$APP_NAME-latest.dmg" "$DELETE_DIR/$APP_NAME-latest-$APP_VERSION.dmg"
fi

if [[ -e "$DIST_DIR/$APP_NAME.dmg" && ! -L "$DIST_DIR/$APP_NAME.dmg" ]]; then
    mv -f "$DIST_DIR/$APP_NAME.dmg" "$DELETE_DIR/$APP_NAME-prev-$APP_VERSION.dmg"
fi

for old_dmg in "$DIST_DIR/$APP_NAME"-*.dmg; do
    if [[ -e "$old_dmg" ]]; then
        mv -f "$old_dmg" "$DELETE_DIR/$(basename "$old_dmg")"
    fi
done

if [[ ! -d "$APP_DIR" ]]; then
    bash "$ROOT_DIR/scripts/build_app.sh"
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
rm -f "$DMG_PATH"
rm -f "$RW_DMG_PATH"

cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG_PATH" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG_PATH" -noverify)"
DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/^\/dev\/disk/ {print $1; exit}')"

if [[ -z "$DEVICE" ]]; then
    echo "Failed to determine mounted DMG device" >&2
    exit 1
fi

VOLUME_PATH="/Volumes/$APP_NAME"
for _ in {1..20}; do
    if [[ -d "$VOLUME_PATH" ]]; then
        break
    fi
    sleep 0.2
done

if [[ ! -d "$VOLUME_PATH" ]]; then
    echo "Failed to mount DMG volume at $VOLUME_PATH" >&2
    exit 1
fi

if ! osascript <<EOF >/dev/null
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set position of item "$APP_NAME.app" to {180, 180}
        set position of item "Applications" to {500, 180}
        update without registering applications
        delay 0.5
        close
    end tell
end tell
EOF
then
    echo "Warning: Failed to persist Finder icon positions. DMG still created." >&2
fi

sync
DETACHED=0
for _ in {1..8}; do
    if hdiutil detach "$DEVICE" -quiet; then
        DETACHED=1
        break
    fi
    sleep 0.5
done

if [[ "$DETACHED" -ne 1 ]]; then
    hdiutil detach "$DEVICE" -force -quiet
fi

hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH" -ov >/dev/null
rm -f "$RW_DMG_PATH"
rm -rf "$STAGE_DIR"

echo "Packaged DMG: $DMG_PATH"
echo "Version: $APP_VERSION"
