#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FrostBar"
BUILD_DIR="$ROOT_DIR/build/app"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
BINARY_PATH="$MACOS_DIR/$APP_NAME"
VERSION_FILE="$ROOT_DIR/build/version.txt"

mkdir -p "$BUILD_DIR"

if [[ -f "$VERSION_FILE" ]]; then
    CURRENT_VERSION="$(cat "$VERSION_FILE")"
elif [[ -f "$PLIST_PATH" ]]; then
    CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH" 2>/dev/null || echo "0.1.0")"
else
    CURRENT_VERSION="0.1.0"
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-1}"
PATCH="${PATCH:-0}"
NEXT_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"

echo "$NEXT_VERSION" > "$VERSION_FILE"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FrostBar</string>
    <key>CFBundleDisplayName</key>
    <string>FrostBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.frostbar.app</string>
    <key>CFBundleVersion</key>
    <string>$NEXT_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$NEXT_VERSION</string>
    <key>CFBundleExecutable</key>
    <string>FrostBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

swiftc \
    "$ROOT_DIR/app-swift/Sources/App/main.swift" \
    -framework AppKit \
    -o "$BINARY_PATH"

chmod +x "$BINARY_PATH"

echo "Built app bundle: $APP_DIR"
echo "Version: $NEXT_VERSION"
