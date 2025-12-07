#!/bin/bash

SOURCE="Assets/icon.png"
ICONSET="Assets/AppIcon.iconset"
DEST="UnifiedAudioControl.app/Contents/Resources/AppIcon.icns"

mkdir -p "$ICONSET"
mkdir -p "UnifiedAudioControl.app/Contents/Resources"

# Resize to standard icon sizes
sips -s format png -z 16 16     "$SOURCE" --out "$ICONSET/icon_16x16.png"
sips -s format png -z 32 32     "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"
sips -s format png -z 32 32     "$SOURCE" --out "$ICONSET/icon_32x32.png"
sips -s format png -z 64 64     "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"
sips -s format png -z 128 128   "$SOURCE" --out "$ICONSET/icon_128x128.png"
sips -s format png -z 256 256   "$SOURCE" --out "$ICONSET/icon_128x128@2x.png"
sips -s format png -z 256 256   "$SOURCE" --out "$ICONSET/icon_256x256.png"
sips -s format png -z 512 512   "$SOURCE" --out "$ICONSET/icon_256x256@2x.png"
sips -s format png -z 512 512   "$SOURCE" --out "$ICONSET/icon_512x512.png"
sips -s format png -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png"

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o "$DEST"

# Clean up iconset
rm -rf "$ICONSET"

echo "Icon created at $DEST"
