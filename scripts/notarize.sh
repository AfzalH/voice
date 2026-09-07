#!/usr/bin/env bash
# Notarizes and staples the DMG produced by create-dmg.sh.
#
# One-time setup (stores an app-specific password in the keychain):
#   xcrun notarytool store-credentials "vBoard-Notary" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"
#
# Usage: ./scripts/notarize.sh [dist/vBoard-3.5.0.dmg]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-vBoard-Notary}"
DMG_PATH="${1:-$(ls -t "$ROOT_DIR"/dist/vBoard-*.dmg 2>/dev/null | head -1)}"

if [[ -z "$DMG_PATH" || ! -f "$DMG_PATH" ]]; then
  echo "No DMG found. Run scripts/create-dmg.sh first." >&2
  exit 1
fi

APP_IN_DMG="$(hdiutil attach -nobrowse -readonly "$DMG_PATH" | awk -F'\t' '/\/Volumes\//{print $NF}')"
trap 'hdiutil detach "$APP_IN_DMG" -quiet 2>/dev/null || true' EXIT
echo "Checking signature of app inside DMG..."
codesign --verify --deep --strict --verbose=2 "$APP_IN_DMG"/vBoard.app
SIGNATURE_INFO="$(codesign -dvv "$APP_IN_DMG"/vBoard.app 2>&1 || true)"
if [[ "$SIGNATURE_INFO" != *"Developer ID Application"* ]]; then
  echo "App is not signed with a Developer ID Application certificate; notarization will be rejected." >&2
  exit 1
fi
hdiutil detach "$APP_IN_DMG" -quiet
trap - EXIT

echo "Submitting $DMG_PATH for notarization (profile: $PROFILE)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait

echo "Stapling ticket..."
xcrun stapler staple "$DMG_PATH"

echo "Verifying Gatekeeper acceptance..."
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
echo "Done: $DMG_PATH is notarized and stapled."
