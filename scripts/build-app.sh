#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="SrizonVoice"
APP_DIR="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_NAME="SrizonVoice"
EXECUTABLE_SOURCE="$BUILD_DIR/$EXECUTABLE_NAME"
EXECUTABLE_DEST="$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
PLIST_PATH="$APP_DIR/Contents/Info.plist"

mkdir -p "$DIST_DIR"

echo "Building release binary..."
swift build -c release --package-path "$ROOT_DIR"

if [[ ! -f "$EXECUTABLE_SOURCE" ]]; then
  echo "Build output not found at $EXECUTABLE_SOURCE"
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE_SOURCE" "$EXECUTABLE_DEST"
chmod +x "$EXECUTABLE_DEST"

# Copy app icon if it exists
if [[ -f "$ROOT_DIR/logo.png" ]]; then
  echo "Converting logo to .icns..."
  ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  
  # Generate different sizes for .icns
  sips -z 16 16     "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
  sips -z 32 32     "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
  sips -z 32 32     "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
  sips -z 64 64     "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
  sips -z 128 128   "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
  sips -z 256 256   "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
  sips -z 256 256   "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
  sips -z 512 512   "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
  sips -z 512 512   "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
  sips -z 1024 1024 "$ROOT_DIR/logo.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1
  
  iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

cat > "$PLIST_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>SrizonVoice</string>
  <key>CFBundleExecutable</key>
  <string>SrizonVoice</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.srizon.voice</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SrizonVoice</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>2.1.0</string>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>SrizonVoice needs microphone access for dictation.</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc signature..."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "App bundle created at:"
echo "  $APP_DIR"
