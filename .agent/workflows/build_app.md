---
description: Build the UnifiedAudioControl.app bundle
---

0. Determine Version
// turbo
```bash
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
if [ -z "$VERSION" ]; then
    echo "ERROR: no git tag found — cannot determine version." >&2
    echo "Tag the release first (e.g. git tag v1.0.4), then re-run." >&2
    exit 1
fi
```

1. Build the release binary
// turbo
```bash
swift build -c release
```

2. Create the App Bundle structure
// turbo
```bash
mkdir -p UnifiedAudioControl.app/Contents/MacOS
mkdir -p UnifiedAudioControl.app/Contents/Resources
```

3. Copy the binary
// turbo
```bash
cp .build/release/UnifiedAudioControl UnifiedAudioControl.app/Contents/MacOS/
```

4. Generate App Icon
// turbo
```bash
sips -s format png -z 16 16     "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_16x16.png"
sips -s format png -z 32 32     "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_16x16@2x.png"
sips -s format png -z 32 32     "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_32x32.png"
sips -s format png -z 64 64     "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_32x32@2x.png"
sips -s format png -z 128 128   "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_128x128.png"
sips -s format png -z 256 256   "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_128x128@2x.png"
sips -s format png -z 256 256   "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_256x256.png"
sips -s format png -z 512 512   "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_256x256@2x.png"
sips -s format png -z 512 512   "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_512x512.png"
sips -s format png -z 1024 1024 "Assets/icon.png" --out "Assets/AppIcon.iconset/icon_512x512@2x.png"
iconutil -c icns "Assets/AppIcon.iconset" -o UnifiedAudioControl.app/Contents/Resources/AppIcon.icns
rm -rf "Assets/AppIcon.iconset"
```

5. Create Info.plist
// turbo
```bash
# Using echo (not a heredoc) to avoid heredoc hangs — see master_build.sh.
PLIST="UnifiedAudioControl.app/Contents/Info.plist"
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$PLIST"
echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$PLIST"
echo '<plist version="1.0">' >> "$PLIST"
echo '<dict>' >> "$PLIST"
echo '    <key>CFBundleExecutable</key><string>UnifiedAudioControl</string>' >> "$PLIST"
echo '    <key>CFBundleIdentifier</key><string>com.akeslo.unifiedaudiocontrol</string>' >> "$PLIST"
echo '    <key>CFBundleName</key><string>UnifiedAudioControl</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>' >> "$PLIST"
echo '    <key>CFBundleShortVersionString</key><string>'$VERSION'</string>' >> "$PLIST"
echo '    <key>CFBundleVersion</key><string>'$VERSION'</string>' >> "$PLIST"
echo '    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Unified Audio Control needs Bluetooth access to detect and connect to your paired devices.</string>
    <key>NSBluetoothPeripheralUsageDescription</key><string>Unified Audio Control needs Bluetooth access to detect and connect to your paired devices.</string>
</dict>' >> "$PLIST"
echo '</plist>' >> "$PLIST"
```

6. Ad-hoc sign the app
// turbo
```bash
codesign --force --deep --sign - UnifiedAudioControl.app
```

7. Reveal in Finder
```bash
open .
```
