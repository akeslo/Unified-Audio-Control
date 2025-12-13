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

## Project Status
- Tested on Apple Silicon and Intel Macs running macOS 13+.
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

## Licensing & Credits
- **MonitorControl** (MIT License) – DDC/CI stack for both IntelDDC and Arm64DDC plus supporting helpers.
- **MultiSoundChanger** (Apache License 2.0) – Aggregate-device handling ideas and UI inspiration for audio switching.

The exact license texts for these dependencies live in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md). Keep that file intact (and update it if you add new upstream code) when publishing this repository so that the original authors receive credit and the permission terms are satisfied.

All original code in Unified Audio Control is released under the [MIT License](LICENSE). Feel free to fork, extend, or ship it commercially—just keep the attribution notices for both this project and the upstream dependencies.
