#!/bin/zsh
set -euo pipefail

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${NOTARY_PROFILE:-}" ]]; then
  echo "Set DEVELOPER_ID_APPLICATION and NOTARY_PROFILE."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/HDR Utility.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/HDR-Utility.dmg}"

codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/Resources/HDRUtility_HDRUtilityKit.bundle/EmbeddedTools/toGainMapHDR"
codesign --force --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/Resources/HDRUtility_HDRUtilityKit.bundle/EmbeddedTools/ultrahdr_bridge"
codesign --force --deep --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

hdiutil create -volname "HDR Utility" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Notarized DMG: $DMG_PATH"
