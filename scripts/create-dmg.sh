#!/usr/bin/env bash
set -euo pipefail

# Script to create a distributable DMG for SrizonVoice
# Usage: ./scripts/create-dmg.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="SrizonVoice"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION="0.1.0"
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"
TEMP_DMG_DIR="$DIST_DIR/dmg-temp"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Creating DMG for $APP_NAME v$VERSION${NC}"

# Step 1: Build the app if it doesn't exist or is outdated
if [[ ! -d "$APP_BUNDLE" ]] || [[ "$ROOT_DIR/Sources" -nt "$APP_BUNDLE" ]]; then
  echo -e "${YELLOW}Building app bundle first...${NC}"
  bash "$ROOT_DIR/scripts/build-app.sh"
fi

# Step 2: Verify app bundle exists
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: App bundle not found at $APP_BUNDLE"
  exit 1
fi

# Step 3: Clean up any previous DMG
if [[ -f "$DMG_PATH" ]]; then
  echo "Removing existing DMG..."
  rm -f "$DMG_PATH"
fi

# Step 4: Create temporary directory for DMG contents
echo "Preparing DMG contents..."
rm -rf "$TEMP_DMG_DIR"
mkdir -p "$TEMP_DMG_DIR"

# Step 5: Copy app bundle to temp directory
cp -R "$APP_BUNDLE" "$TEMP_DMG_DIR/"

# Step 6: Create symbolic link to /Applications
ln -s /Applications "$TEMP_DMG_DIR/Applications"

# Step 7: Create a README for the DMG
cat > "$TEMP_DMG_DIR/README.txt" <<'EOF'
SrizonVoice - Voice Dictation for macOS

INSTALLATION
============
1. Drag SrizonVoice.app to the Applications folder
2. Launch SrizonVoice from Applications or Spotlight
3. Enter your Gladia API key (get one from app.gladia.io)
4. Grant Microphone and Accessibility permissions when prompted

USAGE
=====
- Press Cmd+Shift+D to start/stop dictation
- Click the menu bar icon for language settings
- Use Settings to customize hotkey and API key

FIRST RUN
=========
On first launch, you may see a security warning because this app
is not notarized by Apple. To open:

1. Right-click the app → "Open"
2. Click "Open" in the dialog
3. macOS will remember this choice

REQUIREMENTS
============
- macOS 13.0 (Ventura) or later
- Gladia API key (free tier available at app.gladia.io)
- Microphone and Accessibility permissions

PRIVACY
=======
This app processes audio locally and streams it directly to Gladia's
servers using your personal API key. No data passes through Srizon
servers. Audio is only sent when you actively trigger dictation.

Privacy Policy: https://www.srizon.com/privacy

SUPPORT
=======
For more information, visit: https://github.com/yourusername/voice

EOF

# Step 8: Create the DMG
echo "Creating DMG..."
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$TEMP_DMG_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

# Step 9: Clean up temporary directory
rm -rf "$TEMP_DMG_DIR"

# Step 10: Verify DMG was created
if [[ -f "$DMG_PATH" ]]; then
  DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
  echo -e "${GREEN}✓ DMG created successfully!${NC}"
  echo -e "${GREEN}  Location: $DMG_PATH${NC}"
  echo -e "${GREEN}  Size: $DMG_SIZE${NC}"
  
  # Generate SHA256 checksum
  echo ""
  echo "Generating SHA256 checksum..."
  CHECKSUM=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
  echo "$CHECKSUM  $DMG_NAME.dmg" > "$DIST_DIR/$DMG_NAME.sha256"
  echo -e "${GREEN}✓ Checksum: $CHECKSUM${NC}"
  echo -e "${GREEN}  Saved to: $DIST_DIR/$DMG_NAME.sha256${NC}"
  
  echo ""
  echo -e "${BLUE}Distribution files ready:${NC}"
  echo -e "  📦 $DMG_PATH"
  echo -e "  🔐 $DIST_DIR/$DMG_NAME.sha256"
else
  echo "Error: DMG creation failed"
  exit 1
fi
