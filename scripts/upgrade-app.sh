#!/usr/bin/env bash
# Rebuilds vBoard and replaces the copy in /Applications in place,
# keeping UserDefaults (settings, history) and TCC permissions.
#
# Permissions survive only when the new build is signed with the same stable
# identity as the installed one (see build-app.sh). The first upgrade from an
# ad-hoc-signed build will still need Accessibility and Input Monitoring to be
# granted once more; every upgrade after that keeps them.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/vBoard.app"
TARGET_PATH="/Applications/vBoard.app"

"$ROOT_DIR/scripts/build-app.sh"

if [[ -d "$TARGET_PATH" ]]; then
  OLD_SIG="$(codesign -dv "$TARGET_PATH" 2>&1 | grep -E '^(TeamIdentifier|Authority)=' | head -1 || true)"
  NEW_SIG="$(codesign -dv "$APP_PATH" 2>&1 | grep -E '^(TeamIdentifier|Authority)=' | head -1 || true)"
  if [[ "$OLD_SIG" != "$NEW_SIG" ]]; then
    echo ""
    echo "Note: signing identity changed ($OLD_SIG -> $NEW_SIG)."
    echo "      macOS will ask for Accessibility and Input Monitoring again this one time."
  fi
fi

echo "Stopping running vBoard (if any)..."
pkill -x vBoard 2>/dev/null || true
sleep 1

echo "Replacing $TARGET_PATH ..."
# Replace the bundle *contents* rather than the bundle folder: removing a
# top-level item from /Applications needs the "App Management" privacy
# permission for the terminal, while writing inside a folder we own does not.
if [[ -d "$TARGET_PATH" ]]; then
  rm -rf "${TARGET_PATH:?}"/* "${TARGET_PATH:?}"/.[!.]* 2>/dev/null || true
fi
ditto "$APP_PATH" "$TARGET_PATH"
codesign --verify --deep --strict "$TARGET_PATH"

echo "Launching..."
open "$TARGET_PATH"
echo "Upgrade done. Settings and history were preserved."
