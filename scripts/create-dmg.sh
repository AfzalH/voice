#!/usr/bin/env bash
set -euo pipefail

# Script to create a distributable DMG for SrizonVoice
# with a professional background, drag-and-drop arrow, and icon layout.
# Usage: ./scripts/create-dmg.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="SrizonVoice"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VERSION="2.1.0"
DMG_NAME="$APP_NAME-$VERSION"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"
DMG_TEMP="$DIST_DIR/$DMG_NAME-temp.dmg"
TEMP_DMG_DIR="$DIST_DIR/dmg-staging"
VOL_NAME="$APP_NAME"
WINDOW_WIDTH=660
WINDOW_HEIGHT=400
ICON_SIZE=128

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}Creating DMG for $APP_NAME v$VERSION${NC}"

# Step 0: Detach any previously mounted SrizonVoice volumes to avoid name conflicts
for vol in /Volumes/$VOL_NAME /Volumes/"$VOL_NAME "*/; do
  if mount | grep -q "on ${vol%/} "; then
    dev=$(mount | grep "on ${vol%/} " | awk '{print $1}' | sed 's/s[0-9]*$//')
    echo "Detaching stale volume: ${vol%/}"
    hdiutil detach "$dev" -force -quiet 2>/dev/null || true
  fi
done

# Step 1: Build the app if needed
if [[ ! -d "$APP_BUNDLE" ]] || [[ "$ROOT_DIR/Sources" -nt "$APP_BUNDLE" ]]; then
  echo -e "${YELLOW}Building app bundle first...${NC}"
  bash "$ROOT_DIR/scripts/build-app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: App bundle not found at $APP_BUNDLE"
  exit 1
fi

# Step 2: Generate the background image with drag-and-drop arrow
echo "Generating DMG background..."
BG_DIR="$DIST_DIR/dmg-background"
mkdir -p "$BG_DIR"

python3 - "$BG_DIR/background.png" "$WINDOW_WIDTH" "$WINDOW_HEIGHT" <<'PYEOF'
import sys, struct, zlib

out_path = sys.argv[1]
W, H = int(sys.argv[2]), int(sys.argv[3])

# We work in RGBA pixel buffer
pixels = bytearray(W * H * 4)

def set_pixel(x, y, r, g, b, a=255):
    if 0 <= x < W and 0 <= y < H:
        i = (y * W + x) * 4
        # Alpha blend over existing
        sa = a / 255.0
        da = pixels[i+3] / 255.0
        oa = sa + da * (1 - sa)
        if oa > 0:
            pixels[i]   = int((r * sa + pixels[i]   * da * (1-sa)) / oa)
            pixels[i+1] = int((g * sa + pixels[i+1] * da * (1-sa)) / oa)
            pixels[i+2] = int((b * sa + pixels[i+2] * da * (1-sa)) / oa)
        pixels[i+3] = int(oa * 255)

def fill_rect(x1, y1, x2, y2, r, g, b, a=255):
    for y in range(max(0,y1), min(H,y2)):
        for x in range(max(0,x1), min(W,x2)):
            set_pixel(x, y, r, g, b, a)

def fill_circle(cx, cy, radius, r, g, b, a=255):
    r2 = radius * radius
    for y in range(max(0, int(cy-radius)), min(H, int(cy+radius)+1)):
        for x in range(max(0, int(cx-radius)), min(W, int(cx+radius)+1)):
            if (x-cx)**2 + (y-cy)**2 <= r2:
                set_pixel(x, y, r, g, b, a)

def draw_line(x1, y1, x2, y2, r, g, b, a=255, thickness=2):
    import math
    dx = x2 - x1
    dy = y2 - y1
    length = math.sqrt(dx*dx + dy*dy)
    if length == 0: return
    steps = int(length * 2)
    for i in range(steps + 1):
        t = i / steps
        cx = x1 + dx * t
        cy = y1 + dy * t
        for ty in range(-thickness, thickness+1):
            for tx in range(-thickness, thickness+1):
                if tx*tx + ty*ty <= thickness*thickness:
                    set_pixel(int(cx+tx), int(cy+ty), r, g, b, a)

# Background: dark gradient
for y in range(H):
    t = y / H
    r = int(28 + t * 10)
    g = int(28 + t * 8)
    b = int(35 + t * 12)
    for x in range(W):
        i = (y * W + x) * 4
        pixels[i] = r
        pixels[i+1] = g
        pixels[i+2] = b
        pixels[i+3] = 255

# Subtle radial glow in the center
import math
cx_glow, cy_glow = W // 2, H // 2
max_radius = max(W, H) * 0.6
for y in range(H):
    for x in range(W):
        dist = math.sqrt((x - cx_glow)**2 + (y - cy_glow)**2)
        if dist < max_radius:
            intensity = (1.0 - dist / max_radius) ** 2 * 0.15
            i = (y * W + x) * 4
            pixels[i]   = min(255, int(pixels[i]   + 60 * intensity))
            pixels[i+1] = min(255, int(pixels[i+1] + 50 * intensity))
            pixels[i+2] = min(255, int(pixels[i+2] + 90 * intensity))

# Arrow: pointing right from app icon area to Applications area
# App icon positioned at ~170, Applications at ~490
arrow_y = H // 2 - 10
arrow_x1 = 235
arrow_x2 = 425
arrow_color = (200, 200, 220)

# Dashed arrow shaft
dash_len = 14
gap_len = 10
x = arrow_x1
while x < arrow_x2 - 30:
    end = min(x + dash_len, arrow_x2 - 30)
    draw_line(x, arrow_y, end, arrow_y, *arrow_color, a=180, thickness=2)
    x += dash_len + gap_len

# Arrowhead (triangle pointing right)
tip_x = arrow_x2 - 15
head_size = 16
for offset in range(head_size):
    t = offset / head_size
    half_h = int(head_size * (1 - t) * 0.7)
    ax = tip_x - head_size + offset
    for dy in range(-half_h, half_h + 1):
        alpha = int(200 * (1.0 - abs(dy) / (half_h + 1) * 0.3))
        set_pixel(ax, arrow_y + dy, *arrow_color, a=alpha)

# "Drag to install" text (simple pixel text)
# We'll draw a subtle label below the arrow
label = "drag to install"
char_w, char_h = 6, 1
label_x = (arrow_x1 + arrow_x2) // 2 - len(label) * char_w // 2
label_y = arrow_y + 22

# Simple 5x7 bitmap font for lowercase + space
font = {
    'd': [0x0E,0x12,0x12,0x12,0x0E], 'r': [0x1E,0x10,0x10,0x10,0x10],
    'a': [0x0E,0x02,0x0E,0x12,0x0E], 'g': [0x0E,0x12,0x0E,0x02,0x0C],
    ' ': [0x00,0x00,0x00,0x00,0x00], 't': [0x08,0x1C,0x08,0x08,0x06],
    'o': [0x0E,0x12,0x12,0x12,0x0E], 'i': [0x04,0x00,0x04,0x04,0x04],
    'n': [0x1C,0x12,0x12,0x12,0x12], 's': [0x0E,0x10,0x0E,0x02,0x1C],
    'l': [0x04,0x04,0x04,0x04,0x06], 'e': [0x0E,0x12,0x1E,0x10,0x0E],
}
for ci, ch in enumerate(label):
    glyph = font.get(ch, font[' '])
    for row_i, row in enumerate(glyph):
        for bit in range(5):
            if row & (1 << (4 - bit)):
                px = label_x + ci * 6 + bit
                py = label_y + row_i
                set_pixel(px, py, 180, 180, 200, 140)

# Encode as PNG
def make_png(width, height, rgba_data):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter: none
        offset = y * width * 4
        raw += bytes(rgba_data[offset:offset + width * 4])
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) +
            chunk(b'IEND', b''))

with open(out_path, 'wb') as f:
    f.write(make_png(W, H, pixels))

print(f"Background image created: {W}x{H}")
PYEOF

# Step 3: Clean up previous artifacts
echo "Preparing DMG contents..."
rm -f "$DMG_PATH" "$DMG_TEMP"
rm -rf "$TEMP_DMG_DIR"
mkdir -p "$TEMP_DMG_DIR"

# Step 4: Stage contents
cp -R "$APP_BUNDLE" "$TEMP_DMG_DIR/"
ln -s /Applications "$TEMP_DMG_DIR/Applications"

# Hidden background directory (Finder convention)
mkdir -p "$TEMP_DMG_DIR/.background"
cp "$BG_DIR/background.png" "$TEMP_DMG_DIR/.background/background.png"

# Step 5: Calculate DMG size (contents + 10MB headroom for Finder metadata)
CONTENTS_SIZE_KB=$(du -sk "$TEMP_DMG_DIR" | awk '{print $1}')
DMG_SIZE_MB=$(( (CONTENTS_SIZE_KB / 1024) + 15 ))

# Step 6: Create read-write DMG
echo "Creating read-write DMG..."
hdiutil create -volname "$VOL_NAME" \
  -srcfolder "$TEMP_DMG_DIR" \
  -ov \
  -format UDRW \
  -size "${DMG_SIZE_MB}m" \
  "$DMG_TEMP"

# Step 7: Mount and configure with AppleScript
echo "Configuring DMG layout..."
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify "$DMG_TEMP")
DEVICE=$(echo "$MOUNT_OUTPUT" | grep '/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOL_NAME"

# Wait for Finder to register the volume
sleep 1

# Set custom Finder view using AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, $((100 + WINDOW_WIDTH)), $((100 + WINDOW_HEIGHT))}

    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to $ICON_SIZE
    set background picture of theViewOptions to file ".background:background.png"

    -- Position app icon on the left, Applications on the right
    set position of item "$APP_NAME.app" to {170, 190}
    set position of item "Applications" to {490, 190}

    update without registering applications
    close
  end tell
end tell
APPLESCRIPT

# Give Finder time to write .DS_Store
sync
sleep 2

# Make sure the .DS_Store is flushed
hdiutil detach "$DEVICE" -quiet

# Step 8: Convert to compressed read-only DMG
echo "Compressing DMG..."
hdiutil convert "$DMG_TEMP" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH"

# Step 9: Clean up
rm -f "$DMG_TEMP"
rm -rf "$TEMP_DMG_DIR" "$BG_DIR"

# Step 10: Verify and report
if [[ -f "$DMG_PATH" ]]; then
  DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
  echo -e "${GREEN}DMG created successfully!${NC}"
  echo -e "${GREEN}  Location: $DMG_PATH${NC}"
  echo -e "${GREEN}  Size: $DMG_SIZE${NC}"

  echo ""
  echo "Generating SHA256 checksum..."
  CHECKSUM=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
  echo "$CHECKSUM  $DMG_NAME.dmg" > "$DIST_DIR/$DMG_NAME.sha256"
  echo -e "${GREEN}  Checksum: $CHECKSUM${NC}"

  echo ""
  echo -e "${BLUE}Distribution files:${NC}"
  echo "  $DMG_PATH"
  echo "  $DIST_DIR/$DMG_NAME.sha256"
else
  echo "Error: DMG creation failed"
  exit 1
fi
