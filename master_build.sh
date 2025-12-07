#!/bin/bash
set -e

echo "Starting Clean Build and Bundle..."

# Clean previous artifacts (if any survive)
rm -rf UnifiedAudioControl.app

# 1. Build
echo "Building Release..."
swift build -c release

# 2. Structure
echo "Creating Bundle Structure..."
mkdir -p UnifiedAudioControl.app/Contents/MacOS
mkdir -p UnifiedAudioControl.app/Contents/Resources

# 3. Copy Binary
echo "Copying Binary..."
if [ -f ".build/release/UnifiedAudioControl" ]; then
    cp .build/release/UnifiedAudioControl UnifiedAudioControl.app/Contents/MacOS/
else
    echo "Error: Binary not found at .build/release/UnifiedAudioControl"
    exit 1
fi

# 4. Icon
echo "Setting up Icon..."
if [ -f "Assets/icon.png" ]; then
    ICONSET="Assets/AppIcon.iconset"
    mkdir -p "$ICONSET"
    
    # Generate proper iconset - redirecting sips output to /dev/null to keep build clean
    sips -s format png -z 16 16     "Assets/icon.png" --out "$ICONSET/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "Assets/icon.png" --out "$ICONSET/icon_16x16@2x.png" > /dev/null
    sips -s format png -z 32 32     "Assets/icon.png" --out "$ICONSET/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "Assets/icon.png" --out "$ICONSET/icon_32x32@2x.png" > /dev/null
    sips -s format png -z 128 128   "Assets/icon.png" --out "$ICONSET/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "Assets/icon.png" --out "$ICONSET/icon_128x128@2x.png" > /dev/null
    sips -s format png -z 256 256   "Assets/icon.png" --out "$ICONSET/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "Assets/icon.png" --out "$ICONSET/icon_256x256@2x.png" > /dev/null
    sips -s format png -z 512 512   "Assets/icon.png" --out "$ICONSET/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "Assets/icon.png" --out "$ICONSET/icon_512x512@2x.png" > /dev/null
    
    # Compile to icns
    iconutil -c icns "$ICONSET" -o UnifiedAudioControl.app/Contents/Resources/AppIcon.icns
    
    # Clean up
    rm -rf "$ICONSET"
else
    echo "Warning: Assets/icon.png not found"
fi

# 5. Info.plist (Using echo to avoid heredoc hangs)
echo "Creating Info.plist..."
PLIST="UnifiedAudioControl.app/Contents/Info.plist"
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$PLIST"
echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$PLIST"
echo '<plist version="1.0">' >> "$PLIST"
echo '<dict>' >> "$PLIST"
echo '    <key>CFBundleExecutable</key><string>UnifiedAudioControl</string>' >> "$PLIST"
echo '    <key>CFBundleIdentifier</key><string>com.example.UnifiedAudioControl</string>' >> "$PLIST"
echo '    <key>CFBundleName</key><string>UnifiedAudioControl</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>' >> "$PLIST"
echo '    <key>CFBundleShortVersionString</key><string>1.0.0</string>' >> "$PLIST"
echo '    <key>CFBundleVersion</key><string>1</string>' >> "$PLIST"
echo '    <key>LSUIElement</key><true/>' >> "$PLIST"
echo '    <key>NSHighResolutionCapable</key><true/>' >> "$PLIST"
echo '</dict>' >> "$PLIST"
echo '</plist>' >> "$PLIST"

# 6. Sign
echo "Signing..."
touch UnifiedAudioControl.app
codesign --force --deep --sign - UnifiedAudioControl.app

echo "Build and Bundle Complete!"
ls -lh UnifiedAudioControl.app/Contents/MacOS/UnifiedAudioControl
