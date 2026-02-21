#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_PATH="/Applications/SrizonVoice.app"
BUNDLE_ID="com.srizon.voice"

# -- Clean up previous installation --

echo "Cleaning up previous installation..."

# Quit the app if it's running.
pkill -x SrizonVoice 2>/dev/null && echo "  Stopped running SrizonVoice" || true
sleep 0.5

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

# Reset Accessibility TCC entry so the stale code-signature doesn't block
# the newly-built binary.  The app will re-prompt on first launch.
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null \
    && echo "  Reset Accessibility permission (stale signature cleared)" || true

# Reset Input Monitoring (ListenEvent) TCC entry.
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null \
    && echo "  Reset Input Monitoring permission" || true

# Remove Login Items entry.
osascript -e 'tell application "System Events" to delete (login items whose name is "SrizonVoice")' 2>/dev/null \
    && echo "  Removed Login Items entry" || true

echo "  Cleanup done."
