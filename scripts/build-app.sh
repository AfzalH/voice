#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="SrizonVoice"
APP_DIR="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_NAME="SrizonVoice"
EXECUTABLE_DEST="$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
PLIST_PATH="$APP_DIR/Contents/Info.plist"
VERSION="3.4.0"
BUILD_NUMBER="11"
read -r -a ARCHS <<< "${SRIZONVOICE_ARCHS:-arm64 x86_64}"

if [[ ${#ARCHS[@]} -eq 0 ]]; then
  echo "No architectures configured. Set SRIZONVOICE_ARCHS, for example: SRIZONVOICE_ARCHS=\"arm64 x86_64\""
  exit 1
fi

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

mkdir -p "$DIST_DIR"

ARCH_EXECUTABLES=()
for arch in "${ARCHS[@]}"; do
  echo "Building release binary ($arch, macOS $MACOSX_DEPLOYMENT_TARGET+)..."
  swift build -c release --arch "$arch" --package-path "$ROOT_DIR"

  BIN_PATH="$(swift build -c release --arch "$arch" --show-bin-path --package-path "$ROOT_DIR")"
  ARCH_EXECUTABLE="$BIN_PATH/$EXECUTABLE_NAME"
  if [[ ! -f "$ARCH_EXECUTABLE" ]]; then
    echo "Build output not found at $ARCH_EXECUTABLE"
    exit 1
  fi
  ARCH_EXECUTABLES+=("$ARCH_EXECUTABLE")
done

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

if [[ ${#ARCH_EXECUTABLES[@]} -eq 1 ]]; then
  cp "${ARCH_EXECUTABLES[0]}" "$EXECUTABLE_DEST"
else
  echo "Creating universal binary..."
  lipo -create "${ARCH_EXECUTABLES[@]}" -output "$EXECUTABLE_DEST"
fi
chmod +x "$EXECUTABLE_DEST"
lipo -info "$EXECUTABLE_DEST"

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
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__BUILD_NUMBER__</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>SrizonVoice needs microphone access for dictation.</string>
</dict>
</plist>
EOF

sed -i '' \
  -e "s/__VERSION__/$VERSION/g" \
  -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/g" \
  "$PLIST_PATH"

if command -v codesign >/dev/null 2>&1; then
  echo "Applying ad-hoc signature..."
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "App bundle created at:"
echo "  $APP_DIR"
