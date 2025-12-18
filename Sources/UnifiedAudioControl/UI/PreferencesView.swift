import SwiftUI
import CoreAudio
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject var audioManager: AudioDeviceManager
    @ObservedObject var displayManager: DisplayManager
    
    // Use a sidebar style for modern macOS look
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AudioSettingsView(audioManager: audioManager)
                .tabItem {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
            
            DisplaySettingsView(displayManager: displayManager)
                .tabItem {
                    Label("Display", systemImage: "display")
                }
            
            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            
            UpdateSettingsView()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 600, height: 450)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("showHUD") private var showHUD = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unified Audio Control")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Version 1.0.2")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            Divider()
            
            Form {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        if newValue {
                            do {
                                try SMAppService.mainApp.register()
                                print("DEBUG: Successfully registered for launch at login")
                            } catch {
                                print("DEBUG: Failed to register for launch at login: \(error)")
                                // Revert if failed
                                launchAtLogin = false
                            }
                        } else {
                            do {
                                try SMAppService.mainApp.unregister()
                                print("DEBUG: Successfully unregistered for launch at login")
                            } catch {
                                print("DEBUG: Failed to unregister for launch at login: \(error)")
                            }
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                
                Toggle("Show HUD Overlays", isOn: $showHUD)
                    .toggleStyle(.checkbox)
                
                // Add more general settings here as needed
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Sync state with system
            if SMAppService.mainApp.status == .enabled {
                launchAtLogin = true
            } else {
                launchAtLogin = false
            }
        }
    }
}

struct AudioSettingsView: View {
    @ObservedObject var audioManager: AudioDeviceManager
    @State private var searchText = ""
    
    var filteredDevices: [AudioDevice] {
        if searchText.isEmpty {
            return audioManager.allOutputDevices
        } else {
            return audioManager.allOutputDevices.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(filteredDevices) { device in
                    AudioDeviceRow(device: device, audioManager: audioManager)
                }
            }
            .listStyle(.inset)
        }
        .searchable(text: $searchText, placement: .automatic, prompt: "Search Devices")
    }
}

struct AudioDeviceRow: View {
    let device: AudioDevice
    @ObservedObject var audioManager: AudioDeviceManager
    @State private var name: String = ""
    
    var isActive: Bool {
        !audioManager.ignoredDeviceUIDs.contains(device.uid)
    }
    
    var body: some View {
        HStack {
            Image(systemName: device.transportType == kAudioDeviceTransportTypeBluetooth ? "airpods" : "speaker.wave.2.fill")
                .foregroundColor(isActive ? .blue : .secondary)
                .opacity(isActive ? 1.0 : 0.5)
                .frame(width: 20)
            
            TextField(device.name, text: $name, onCommit: {
                audioManager.setCustomName(deviceID: device.id, name: name)
                if name.isEmpty {
                    name = device.name
                }
            })
            .textFieldStyle(.roundedBorder)
            .disabled(!isActive)
            .opacity(isActive ? 1.0 : 0.5)
            
            Spacer()
            
            Toggle("Visible", isOn: Binding(
                get: { isActive },
                set: { isActive in
                    audioManager.setVisibility(uid: device.uid, visible: isActive)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .onAppear {
            name = audioManager.customNames[device.uid] ?? ""
        }
    }
}

struct DisplaySettingsView: View {
    @ObservedObject var displayManager: DisplayManager
    @State private var searchText = ""
    
    var filteredDisplays: [DisplayInfo] {
        if searchText.isEmpty {
            return displayManager.allDisplays
        } else {
            return displayManager.allDisplays.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(filteredDisplays) { display in
                    DisplayRow(display: display, displayManager: displayManager)
                }
            }
            .listStyle(.inset)
        }
        .searchable(text: $searchText, placement: .automatic, prompt: "Search Displays")
    }
}

struct DisplayRow: View {
    let display: DisplayInfo
    @ObservedObject var displayManager: DisplayManager
    @State private var name: String = ""
    
    var isActive: Bool {
        !displayManager.ignoredDisplayUUIDs.contains(display.uuid)
    }
    
    var body: some View {
        HStack {
            Image(systemName: "display")
                .foregroundColor(isActive ? .blue : .secondary)
                .opacity(isActive ? 1.0 : 0.5)
                .frame(width: 20)
            
            TextField(display.name, text: $name, onCommit: {
                displayManager.setCustomName(displayID: display.id, name: name)
                if name.isEmpty {
                    name = display.name
                }
            })
            .textFieldStyle(.roundedBorder)
            .disabled(!isActive)
            .opacity(isActive ? 1.0 : 0.5)
            
            Spacer()
            
            Toggle("Visible", isOn: Binding(
                get: { isActive },
                set: { isActive in
                    displayManager.setVisibility(uuid: display.uuid, visible: isActive)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .onAppear {
            name = displayManager.customNames[display.uuid] ?? ""
        }
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var hotKeyManager = HotKeyManager.shared
    @State private var isRecording = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keyboard Shortcuts")
                .font(.headline)
            
            Form {
                Section {
                    HStack {
                        Text("Toggle Menu")
                        Spacer()
                        
                        Button(action: {
                            isRecording = true
                        }) {
                            if isRecording {
                                Text("Press keys...")
                                    .foregroundColor(.blue)
                            } else if let hotKey = hotKeyManager.currentHotKey {
                                Text(hotKeyManager.keyString(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers))
                            } else {
                                Text("Record Shortcut")
                            }
                        }
                        .buttonStyle(.bordered)
                        .background(ShortcutRecorder(isRecording: $isRecording))
                        
                        if hotKeyManager.currentHotKey != nil {
                            Button(action: {
                                hotKeyManager.unregister()
                                hotKeyManager.currentHotKey = nil
                                UserDefaults.standard.removeObject(forKey: "globalHotKeyKeyCode")
                                UserDefaults.standard.removeObject(forKey: "globalHotKeyModifiers")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Spacer()
        }
        .padding()
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    
    func makeNSView(context: Context) -> FocusableView {
        let view = FocusableView()
        view.onKeyDown = { event in
            if isRecording {
                if event.keyCode == 53 { // Escape
                    isRecording = false
                    return
                }
                
                HotKeyManager.shared.register(keyCode: Int(event.keyCode), modifiers: Int(event.modifierFlags.rawValue))
                isRecording = false
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: FocusableView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class FocusableView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}
