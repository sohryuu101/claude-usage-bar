#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Claude Usage Bar"
BUNDLE_ID="${BUNDLE_ID:-dev.local.claude-usage-bar}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
APP_PATH="$STAGING_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/ClaudeUsageBar.dmg"
TEMP_DMG="$DIST_DIR/ClaudeUsageBar.temp.dmg"

rm -rf "$DIST_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

swift build -c release \
  --arch arm64 \
  --scratch-path "$ROOT_DIR/.build/apple"

BUILT_EXECUTABLE="$(find "$ROOT_DIR/.build/apple" -path '*/release/ClaudeUsageBar' -type f | head -n 1)"
if [[ -z "$BUILT_EXECUTABLE" ]]; then
  echo "Release executable not found" >&2
  exit 1
fi

cp "$BUILT_EXECUTABLE" "$APP_PATH/Contents/MacOS/ClaudeUsageBar"
chmod +x "$APP_PATH/Contents/MacOS/ClaudeUsageBar"

/usr/libexec/PlistBuddy -c "Clear dict" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ClaudeUsageBar" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.0.0" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Local usage monitor" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_PATH"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TEMP_DMG"

hdiutil convert "$TEMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

rm -f "$TEMP_DMG"

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
