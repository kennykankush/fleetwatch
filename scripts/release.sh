#!/bin/bash
# Stockpile release pipeline: archive → export (Developer ID) → notarize → staple → zip
# One-time setup: xcrun notarytool store-credentials stockpile \
#   --apple-id <apple-id> --team-id 483LU3J5WJ --password <app-specific-password>
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=$(grep MARKETING_VERSION project.yml | awk '{print $2}' | tr -d '"')
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/Stockpile.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
ZIP="$BUILD_DIR/Stockpile-$VERSION.zip"

echo "▸ Generating project…"
xcodegen generate

echo "▸ Archiving (Release)…"
xcodebuild archive \
    -project Stockpile.xcodeproj \
    -scheme Stockpile \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM=483LU3J5WJ \
    CODE_SIGN_STYLE=Automatic \
    | grep -E "error|ARCHIVE" || true

echo "▸ Exporting with Developer ID…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    | grep -E "error|EXPORT" || true

APP="$EXPORT_DIR/Stockpile.app"
codesign --verify --deep --strict "$APP" && echo "▸ Signature valid."

echo "▸ Zipping for notarization…"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "▸ SKIP_NOTARIZE=1 — stopping before notarization. App at: $APP"
    exit 0
fi

echo "▸ Submitting to Apple notary service (waits for verdict)…"
xcrun notarytool submit "$ZIP" --keychain-profile stockpile --wait

echo "▸ Stapling ticket to the app…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP" && echo "▸ Staple valid."

echo "▸ Re-zipping stapled app…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✅ Done: $ZIP — notarized, stapled, ready to distribute."
