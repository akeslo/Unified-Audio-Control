# Unified Audio Control

Unified Audio Control is a native Swift/SwiftUI menu bar utility for macOS that keeps audio devices, system volume, and external monitor controls in one popover. It blends an Aggregate-device aware volume controller inspired by **MultiSoundChanger** with the proven DDC/CI stack from **MonitorControl**, resulting in a single place to manage speakers, headsets, and displays.

## What You Can Do

### 🎧 Audio Device Control
- Switch between every CoreAudio output device without opening System Settings.
- Control master volume & mute, even for Aggregate Devices that macOS refuses to show a slider for.
- Rename or hide devices you do not care about, and let the app automatically follow hot‑plug events for Bluetooth/USB hardware.

### 🖥️ Display & DDC/CI Control
- Adjust brightness for both Apple-built panels and external displays using MonitorControl’s Intel + Apple Silicon DDC implementations.
- When a display is also the active audio output, a dedicated slider lets you send DDC volume changes from the same UI.
- Collapse/expand the list of displays straight from the popover, keeping the menu bar experience minimal.

### ✨ Quality-of-Life
- HUD overlays mimic macOS’ native brightness/volume heads-up display whenever you adjust sliders.
- A global hotkey (configurable in Preferences) toggles the popover so you never have to click the status icon.
- Preferences include launch-at-login, visibility toggles, and per-device/per-display custom names to keep lists tidy.
- Media keys (volume up/down/mute) are handled directly, showing the same HUD as the in-app sliders.
- Built-in updater checks GitHub Releases and can install new versions from the Preferences window.

## Project Status
- Requires macOS 14 or later (`Package.swift` declares `.macOS(.v14)`); tested on Apple Silicon and Intel Macs.
- Audio device switching, brightness control, and HUDs are functional today.
- Per-app audio routing is intentionally deferred until there is a redistributable driver solution.

## Build & Run
1. Clone the repository:
   ```bash
   git clone https://github.com/akeslo/Unified-Audio-Control.git
   cd Unified-Audio-Control
   ```
2. Build/launch the menu bar app:
   ```bash
   swift run
   ```
3. Grant the requested permissions (Accessibility for hotkeys, Screen Recording for display metadata) when macOS prompts.

No third-party audio drivers are required—everything relies on CoreAudio and the bundled DDC helper.

## Troubleshooting

### Build fails during version tag parsing or update checks
If the build fails with an error about parsing version tags or checking for updates, ensure `master_build.sh` is up to date with the latest `Package.swift` version. The version string must follow semantic versioning (`X.Y.Z`); tags with extra metadata (e.g., `v1.0.3-beta`) are rejected by the parser.

### Info.plist is out of sync
The build process synchronizes `Info.plist` between the app bundle and the workflow documentation in `build_app.md`. If you see errors about missing or mismatched plist keys during build, run `./master_build.sh` to regenerate both from the canonical source.

### Update checker is not running on launch
The app defaults to checking GitHub Releases on startup for newer versions. If you see update-check errors in the console, ensure you have network access and that your GitHub API connection is stable. The check runs asynchronously and does not block app startup.

### Build artifacts are cluttering the repository
The `.gitignore` rule excludes `UnifiedAudioControl.app/` and build intermediates. If you see the app binary appearing in `git status`, verify that `.gitignore` has not been accidentally modified and that you are not using `git add -f` to force-track build products.

## Licensing & Credits
- **MonitorControl** (MIT License) – DDC/CI stack for both IntelDDC and Arm64DDC plus supporting helpers.
- **MultiSoundChanger** (Apache License 2.0) – Aggregate-device handling ideas and UI inspiration for audio switching.

The exact license texts for these dependencies live in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md). Keep that file intact (and update it if you add new upstream code) when publishing this repository so that the original authors receive credit and the permission terms are satisfied.

All original code in Unified Audio Control is released under the [MIT License](LICENSE). Feel free to fork, extend, or ship it commercially—just keep the attribution notices for both this project and the upstream dependencies.
