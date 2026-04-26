#!/usr/bin/env bash
# Build MyShikiPlayer (Release), pack MyShikiPlayer.app into a compressed DMG, open it.
# By default bumps CURRENT_PROJECT_VERSION in Configuration/Version.xcconfig by 1 before the build.
# Disable with: SKIP_BUILD_NUMBER_BUMP=1 ./scripts/build-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="${SCHEME:-MyShikiPlayer}"
CONFIGURATION="${CONFIGURATION:-Release}"
# generic macOS = universal build when the project supports it
DESTINATION="${DESTINATION:-generic/platform=macOS}"

BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
DERIVED="$BUILD_ROOT/DerivedData"
STAGING="$BUILD_ROOT/dmg_staging"
APP_NAME="MyShikiPlayer"
VOL_NAME="${DMG_VOLUME_NAME:-$APP_NAME}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
OUTPUT_DMG="$BUILD_ROOT/$DMG_NAME"

VERSION_FILE="${VERSION_FILE:-$ROOT/Configuration/Version.xcconfig}"

bump_build_number() {
  if [[ -n "${SKIP_BUILD_NUMBER_BUMP:-}" ]]; then
    echo "==> skipping build-number bump (SKIP_BUILD_NUMBER_BUMP is set)"
    return 0
  fi
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "error: $VERSION_FILE not found" >&2
    exit 1
  fi
  local line current
  line=$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=' "$VERSION_FILE" | grep -v '^[[:space:]]*//' | tail -n 1 || true)
  if [[ -z "$line" ]]; then
    echo "error: $VERSION_FILE has no CURRENT_PROJECT_VERSION line" >&2
    exit 1
  fi
  current=$(echo "$line" | sed -E 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*([0-9]+).*/\1/')
  if ! [[ "$current" =~ ^[0-9]+$ ]]; then
    echo "error: failed to parse build number from: $line" >&2
    exit 1
  fi
  local next=$((current + 1))
  # Quote split so that sed does not read \1 plus the build digits as a single backreference (e.g. \16).
  sed -i '' -E 's/^([[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*)[0-9]+/\1'"$next"'/' "$VERSION_FILE"
  echo "==> build number: $current → $next ($VERSION_FILE)"
}

bump_build_number

mkdir -p "$BUILD_ROOT"

echo "==> xcodebuild ($CONFIGURATION) → $DERIVED"
xcodebuild \
  -project "$ROOT/MyShikiPlayer.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  build

APP_PATH="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app at $APP_PATH" >&2
  exit 1
fi

echo "==> staging DMG contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
# Familiar "drag to Applications" hint shown inside the mounted DMG.
ln -sf /Applications "$STAGING/Applications"

echo "==> hdiutil → $OUTPUT_DMG"
rm -f "$OUTPUT_DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "==> open $OUTPUT_DMG"
open "$OUTPUT_DMG"
