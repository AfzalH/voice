#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/SrizonVoice.app"
TARGET_PATH="/Applications/SrizonVoice.app"
BUNDLE_ID="com.srizon.voice"

# -- Clean up previous installation --

echo "Cleaning up previous installation..."

# Quit the app if it's running.
pkill -x SrizonVoice 2>/dev/null && echo "  Stopped running SrizonVoice" || true
sleep 0.5

# Reset TCC permissions before removing the bundle, so macOS can still
# resolve the bundle identifier and clear stale code-signature grants.
reset_tcc_permission() {
    local service="$1"
    local label="$2"
    local output
    if output=$(tccutil reset "$service" "$BUNDLE_ID" 2>&1); then
        echo "  Reset $label permission"
    else
        echo "  Could not reset $label permission: $output"
    fi
}

reset_tcc_permission Microphone "Microphone"
reset_tcc_permission Accessibility "Accessibility"
reset_tcc_permission ListenEvent "Input Monitoring"

# Remove the installed app.
rm -rf "$TARGET_PATH" && echo "  Removed $TARGET_PATH" || true

# Remove Keychain entry (leftover from older versions).
security delete-generic-password -s "$BUNDLE_ID" -a "gladia-api-key" 2>/dev/null \
    && echo "  Removed Keychain entry" || true

# Remove UserDefaults / preferences.
defaults delete "$BUNDLE_ID" 2>/dev/null && echo "  Removed UserDefaults" || true
rm -f ~/Library/Preferences/${BUNDLE_ID}.plist

# Remove HTTP storages.
rm -rf ~/Library/HTTPStorages/${BUNDLE_ID}

# Remove caches.
rm -rf ~/Library/Caches/${BUNDLE_ID}

# Remove saved application state.
rm -rf ~/Library/Saved\ Application\ State/${BUNDLE_ID}.savedState

# Remove Login Items entry.
osascript -e 'tell application "System Events" to delete (login items whose name is "SrizonVoice")' 2>/dev/null \
    && echo "  Removed Login Items entry" || true

echo "  Cleanup done."
echo ""

# -- Build and install --

 "$ROOT_DIR/scripts/build-app.sh"

 echo "Installing to /Applications..."
 cp -R "$APP_PATH" "$TARGET_PATH"

 echo ""
 echo "Installed:"
 echo "  $TARGET_PATH"
 echo "You can launch it from Spotlight or Applications."
