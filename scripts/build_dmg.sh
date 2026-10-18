#!/bin/bash
# Builds a Release .app and packages it into a distributable DMG. Used by both local testing and
# .github/workflows/release.yml, so the packaging logic lives in exactly one place. Ad-hoc signed
# only (project.yml: CODE_SIGN_IDENTITY "-") — no Apple Developer account involved, so downloaders
# see a one-time Gatekeeper "unidentified developer" prompt (right-click > Open) on first launch.
#
# Usage: scripts/build_dmg.sh [version]
#   version defaults to project.yml's own MARKETING_VERSION.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Hush"
VERSION="${1:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)}"
BUILD_DIR="$(pwd)/.release-build"
STAGING_DIR="$(pwd)/.dmg-staging"
DMG_PATH="$(pwd)/${APP_NAME}-${VERSION}.dmg"

rm -rf "$BUILD_DIR" "$STAGING_DIR"
rm -f "$DMG_PATH"

xcodegen generate

xcodebuild \
  -project JBLCompanion.xcodeproj \
  -scheme JBLCompanion \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  MARKETING_VERSION="$VERSION" \
  clean build

APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING_DIR" "$BUILD_DIR"

echo "Built $DMG_PATH"
