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
# Sparkle's update check compares CFBundleVersion (CURRENT_PROJECT_VERSION), not
# CFBundleShortVersionString (MARKETING_VERSION) — project.yml's own CURRENT_PROJECT_VERSION
# ("1") was never bumped per release, so every build ever shipped had the literal same build
# number. Sparkle's comparator read that as "1" > "0.2.0" (component-wise: 1 > 0), so it always
# reported "up to date" no matter what the feed actually offered — no release has ever
# auto-updated. A UTC timestamp is a simple, always-increasing build number with no extra state
# to track between CI runs.
BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)"
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
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  clean build

# scripts/update_appcast.sh reads this to put the SAME build number in the feed's
# <sparkle:version> — that element is what Sparkle actually compares against the installed app's
# CFBundleVersion (sparkle:shortVersionString is display-only). Written outside BUILD_DIR/
# STAGING_DIR so it survives this script's own rm -rf of those.
echo -n "$BUILD_NUMBER" > "$(pwd)/.sparkle-build-number"

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
