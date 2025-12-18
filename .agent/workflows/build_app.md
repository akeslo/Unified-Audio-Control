---
description: Build the UnifiedAudioControl.app bundle
---

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

3. Generate App Icon
// turbo
```bash
./create_icon.sh
```

3. Copy the binary
// turbo
```bash
cp .build/release/UnifiedAudioControl UnifiedAudioControl.app/Contents/MacOS/
```

4. Create Info.plist
// turbo
```bash
cat > UnifiedAudioControl.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>UnifiedAudioControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.UnifiedAudioControl</string>
    <key>CFBundleName</key>
    <string>UnifiedAudioControl</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.3</string>
    <key>CFBundleVersion</key>
    <string>1.0.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>UnifiedAudioControl uses Bluetooth to detect and manage audio devices.</string>
</dict>
</plist>
EOF
```

5. Ad-hoc sign the app
// turbo
```bash
codesign --force --deep --sign - UnifiedAudioControl.app
```

6. Reveal in Finder
```bash
open .
```
