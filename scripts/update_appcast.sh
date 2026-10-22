#!/bin/bash
# Signs a built DMG with Sparkle's EdDSA key and prepends a matching <item> to appcast.xml.
# Run from CI only (release.yml) right after scripts/build_dmg.sh — needs SPARKLE_PRIVATE_KEY in
# the environment (the private half of the key pair generate_keys produced; the public half lives
# in project.yml's SUPublicEDKey, not a secret). Never run this with a key you haven't put in the
# SPARKLE_PRIVATE_KEY GitHub Actions secret — it is never written to disk here, only piped
# straight into sign_update's stdin.
#
# Usage: scripts/update_appcast.sh <version> <dmg_path> <download_url>
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$1"
DMG_PATH="$2"
DOWNLOAD_URL="$3"

# scripts/build_dmg.sh writes the actual CFBundleVersion it stamped the build with here.
# <sparkle:version> below must match that exactly — it's what Sparkle's update check compares
# against the installed app's own CFBundleVersion, not MARKETING_VERSION/VERSION above (that's
# only <sparkle:shortVersionString>, for display). Falls back to VERSION for a manual/local run
# that skipped build_dmg.sh, though that would reintroduce the same comparison bug this exists to
# fix, so CI should never actually hit this fallback.
BUILD_NUMBER_FILE="$(pwd)/.sparkle-build-number"
BUILD_NUMBER="$([ -f "$BUILD_NUMBER_FILE" ] && cat "$BUILD_NUMBER_FILE" || echo "$VERSION")"

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "error: SPARKLE_PRIVATE_KEY is not set" >&2
  exit 1
fi

SPARKLE_TOOLS_DIR="$(pwd)/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ]; then
  mkdir -p "$SPARKLE_TOOLS_DIR"
  curl -sL -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz
  tar -xf /tmp/sparkle.tar.xz -C "$SPARKLE_TOOLS_DIR"
  rm -f /tmp/sparkle.tar.xz
fi

# `-s <key>`/`-s -` is deprecated and, per `sign_update --help`, "no longer supported for newly
# generated keys" — it fails outright (confirmed: v0.1.2's release run died here with no other
# output). `--ed-key-file -` is the documented replacement for feeding the key over stdin without
# touching disk; `-p` prints just the bare signature (not wrapped in a `sparkle:edSignature="..."`
# attribute), so `length` is built separately below instead of relying on sign_update's own
# attribute-string output.
SIGNATURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_TOOLS_DIR/bin/sign_update" "$DMG_PATH" --ed-key-file - -p)"
LENGTH="$(stat -f%z "$DMG_PATH")"
PUB_DATE="$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"

NEW_ITEM=$(cat <<EOF
    <item>
      <title>Hush ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_URL}" sparkle:edSignature="${SIGNATURE}" length="${LENGTH}" type="application/octet-stream" />
    </item>
EOF
)

# Inserts the new item right after the opening <channel> tag (so items stay newest-first, which
# is Sparkle's own expected order) rather than rebuilding the whole file with an XML tool — the
# feed's shape is simple and fixed enough that this is the lower-risk option. `sed`'s `r` command
# reads a whole file in as a block, unlike `awk -v`'s `-v` assignment: BSD awk (macOS, the same
# runner this runs on) rejects a multi-line string passed that way with "newline in string" —
# confirmed by v0.1.3's own failed run — so the new item goes to a temp file first instead.
ITEM_FILE="$(mktemp)"
printf '%s\n' "$NEW_ITEM" > "$ITEM_FILE"
sed "/<channel>/r $ITEM_FILE" appcast.xml > appcast.xml.tmp
mv appcast.xml.tmp appcast.xml
rm -f "$ITEM_FILE"

rm -f "$BUILD_NUMBER_FILE"

echo "Updated appcast.xml with ${VERSION} (build ${BUILD_NUMBER})"
