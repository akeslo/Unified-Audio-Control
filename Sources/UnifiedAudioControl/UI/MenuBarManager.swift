import SwiftUI
import AppKit
import Combine

class MenuBarManager: NSObject {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var eventMonitor: EventMonitor?
    private var cancellables = Set<AnyCancellable>()
    
    let audioManager = AudioDeviceManager()
    let displayManager = DisplayManager()
    let bluetoothManager = BluetoothManager()
    @Published var currentVolume: Float = 0.0
    
    static let shared = MenuBarManager()
    
    override init() {
        super.init()
        
        // Delay setup to next run loop to avoid layout issues during app init
        DispatchQueue.main.async {
            self.setupMenuBar()
        }
        
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, let popover = strongSelf.popover {
                if popover.isShown {
                    strongSelf.closePopover(sender: event)
                }
            }
        }
        
        // Setup HotKey
        HotKeyManager.shared.toggleHandler = { [weak self] in
            self?.togglePopover(nil)
        }
        
        // Subscribe to relevant changes to update the icon and currentVolume
        audioManager.$volume
            .combineLatest(audioManager.$isMuted)
            .combineLatest(audioManager.$canControlVolume) { ($0.0, $0.1, $1) } // Combine (volume, isMuted) with canControlVolume
            .combineLatest(audioManager.$selectedDeviceID) { ($0.0, $0.1, $0.2, $1) } // Combine (volume, isMuted, canControlVolume) with selectedDeviceID
            .combineLatest(displayManager.$displays) { ($0.0, $0.1, $0.2, $0.3, $1) } // Combine (volume, isMuted, canControlVolume, selectedDeviceID) with displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] volume, isMuted, canControlVolume, selectedDeviceID, displays in
                self?.updateCurrentVolumeAndIcon(
                    volume: volume,
                    isMuted: isMuted,
                    canControlVolume: canControlVolume,
                    selectedDeviceID: selectedDeviceID,
                    displays: displays
                )
            }
            .store(in: &cancellables)

        // Ensure the initial state is up-to-date
        audioManager.updateCurrentState()
    }

    private func updateCurrentVolumeAndIcon(volume: Float, isMuted: Bool, canControlVolume: Bool, selectedDeviceID: AudioDevice.ID, displays: [DisplayInfo]) {
        if canControlVolume {
            currentVolume = volume
        } else {
            // Find the selected display that is also the audio output
            if let selectedDisplay = displays.first(where: { self.isSelectedAudioDevice(display: $0) }) {
                currentVolume = selectedDisplay.volume
            } else {
                // Fallback to audioManager.volume if no DDC display is selected
                currentVolume = volume
            }
        }
        updateIcon()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            updateIcon() // Set initial icon
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
        popover?.behavior = .transient
    }

    func updateIcon() {
        let imageName: String
        let volume = self.currentVolume
        
        if self.audioManager.isMuted {
            imageName = "speaker.slash.fill"
        } else if volume == 0 {
            imageName = "speaker.fill"
        } else if volume <= 0.33 {
            imageName = "speaker.wave.1.fill"
        } else if volume <= 0.66 {
            imageName = "speaker.wave.2.fill"
        } else {
            imageName = "speaker.wave.3.fill"
        }
        
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Audio Control")
            image?.isTemplate = true
            button.image = image
        }
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if let popover = popover {
            if popover.isShown {
                closePopover(sender: sender)
            } else {
                showPopover(sender: sender)
            }
        }
    }
    
    func showPopover(sender: Any?) {
        // Lazily create the content view controller
        if popover?.contentViewController == nil {
            popover?.contentViewController = NSHostingController(rootView: MenuBarView(
                menuBarManager: self,
                audioManager: audioManager,
                displayManager: displayManager,
                bluetoothManager: bluetoothManager
            ))
        }
        
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            eventMonitor?.start()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func closePopover(sender: Any?) {
        popover?.performClose(sender)
        eventMonitor?.stop()
    }
    
    func openPreferences() {
        PreferencesWindowController.shared.showWindow()
        
        // Close popover when opening preferences
        closePopover(sender: nil)
    }

    func isSelectedAudioDevice(display: DisplayInfo) -> Bool {
        guard let selectedDevice = audioManager.outputDevices.first(where: { $0.id == audioManager.selectedDeviceID }) else {
            return false
        }
        
        // 1. Check for UID/UUID match (Strongest)
        // Audio Device UID often contains the Display UUID or Serial
        // Example Audio UID: "05E39027-0000-0000-1C1F-0103803C2278"
        // Example Display UUID: "05E39027-0000-0000-1C1F-0103803C2278" (if fetched correctly)
        // Or sometimes Audio UID is "AppleHDAEngineOutput:..." containing the serial.
        
        if !display.uuid.isEmpty && selectedDevice.uid.contains(display.uuid) {
            return true
        }
        
        // 2. Check for built-in match
        if display.isBuiltIn && selectedDevice.isBuiltIn {
            return true
        }
        
        // 3. Fallback to name match (Weakest)
        return selectedDevice.name.contains(display.name) || display.name.contains(selectedDevice.name)
    }
}

class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    public init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    public func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    public func stop() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }
    }
}

struct MenuBarView: View {
    var menuBarManager: MenuBarManager?
    @ObservedObject var audioManager: AudioDeviceManager
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var bluetoothManager: BluetoothManager
    
    @State private var isBrightnessExpanded: Bool = false
    @State private var isBluetoothExpanded: Bool = false
    
    var isCurrentAudioDeviceCoveredByDisplay: Bool {
        for display in displayManager.displays {
            if menuBarManager?.isSelectedAudioDevice(display: display) ?? false {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unified Audio Control")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Output Device Selection
            VStack(alignment: .leading) {
                Picker("Output Device", selection: $audioManager.selectedDeviceID) {
                    ForEach(audioManager.outputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding(.horizontal)
                .onChange(of: audioManager.selectedDeviceID) { _, newValue in
                    audioManager.selectDevice(deviceID: newValue)
                    
                    // Auto-expand if selected device is a display
                    if let selectedDevice = audioManager.outputDevices.first(where: { $0.id == newValue }) {
                        for display in displayManager.displays {
                            // Check for built-in match or name match
                            let isMatch = (display.isBuiltIn && selectedDevice.isBuiltIn) ||
                                          selectedDevice.name.contains(display.name) ||
                                          display.name.contains(selectedDevice.name)
                            
                            if isMatch {
                                withAnimation {
                                    isBrightnessExpanded = true
                                }
                                break
                            }
                        }
                    }
                }
            }
            
            // Bluetooth Devices Section
            // Combine disconnected devices and connected devices that aren't active audio outputs
            let availableBluetooth = bluetoothManager.recentDevices.filter { device in
                // Include if:
                // 1. Not connected (Disconnected)
                // 2. Connected but not currently in the audio output list (Standby/Multipoint)
                
                if !device.isConnected { return true }
                
                // For connected devices, check if they are already an available output
                // If they ARE in the output list, we don't need to show them here (user can select them from the top picker)
                // If they are NOT in the output list, show them here so user can "Connect" (force switch)
                let isKnownOutput = audioManager.outputDevices.contains { audioDevice in
                    // Fuzzy match name
                    audioDevice.name.localizedCaseInsensitiveContains(device.name) ||
                    device.name.localizedCaseInsensitiveContains(audioDevice.name)
                }
                
                return !isKnownOutput
            }
            
            if !availableBluetooth.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Available Bluetooth")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                isBluetoothExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "airpods")
                                .foregroundColor(isBluetoothExpanded ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    if isBluetoothExpanded {
                        ForEach(availableBluetooth) { device in
                            HStack {
                                Image(systemName: "airpods")
                                    .foregroundColor(device.isConnected ? .blue : .secondary) // Show blue if technically connected
                                
                                Text(device.name)
                                    .font(.callout)
                                
                                Spacer()
                                
                                Button(action: {
                                    bluetoothManager.connect(device: device)
                                }) {
                                    if device.isConnected {
                                        Text("Connected")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    } else {
                                        Text("Connect")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(device.isConnected)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            
            // Volume Control (Global) - Hide if covered by display
            if audioManager.canControlVolume && !isCurrentAudioDeviceCoveredByDisplay {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Volume")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(audioManager.volume * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    HStack {
                        Button(action: {
                            audioManager.toggleMute()
                        }) {
                            Image(systemName: audioManager.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                        }
                        .buttonStyle(.plain)
                        
                        Slider(value: $audioManager.volume, in: 0...1) { editing in
                            if !editing {
                                audioManager.setVolume(audioManager.volume)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            if !displayManager.displays.isEmpty {
                Divider()
                
                VStack(alignment: .leading) {
                    HStack {
                        Text("Displays")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation {
                                isBrightnessExpanded.toggle()
                            }
                        }) {
                            Image(systemName: "display")
                                .foregroundColor(isBrightnessExpanded ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    
                    if isBrightnessExpanded {
                        ForEach($displayManager.displays) { displayBinding in
                            let display = displayBinding.wrappedValue
                            VStack(alignment: .leading, spacing: 4) {
                                Text(display.name)
                                    .font(.caption2)
                                    .padding(.horizontal)
                                
                                HStack {
                                    Image(systemName: "sun.max.fill")
                                        .imageScale(.small)
                                    
                                    Slider(value: Binding(get: {
                                        display.brightness
                                    }, set: { newValue in
                                        displayBinding.brightness.wrappedValue = newValue
                                        displayManager.setBrightness(displayID: display.id, value: newValue)
                                    }), in: 0...1)
                                }
                                .padding(.horizontal)
                                
                                // Only show volume slider if this display is the selected audio device
                                if menuBarManager?.isSelectedAudioDevice(display: display) ?? false {
                                    // Volume Slider
                                    HStack {
                                        Image(systemName: audioManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .imageScale(.small)
                                            .onTapGesture {
                                                audioManager.toggleMute()
                                            }
                                        
                                        Slider(value: Binding<Float>(get: {
                                            if !audioManager.canControlVolume {
                                                return display.volume
                                            }
                                            return audioManager.volume
                                        }, set: { newValue in
                                            if !audioManager.canControlVolume {
                                                displayManager.setVolume(displayID: display.id, value: newValue)
                                            } else {
                                                audioManager.volume = newValue
                                                audioManager.setVolume(newValue)
                                            }
                                        }), in: 0...1) { editing in
                                            if !editing {
                                                if !audioManager.canControlVolume {
                                                    // DDC write is already debounced in DisplayManager
                                                } else {
                                                    audioManager.setVolume(audioManager.volume)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            HStack {
                Button("Preferences...") {
                    menuBarManager?.openPreferences()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .padding(.top, 12)
        .onAppear {
            // Auto-expand if selected device is a display (initial state)
            if audioManager.selectedDeviceID != 0 {
                for display in displayManager.displays {
                    if menuBarManager?.isSelectedAudioDevice(display: display) ?? false {
                        isBrightnessExpanded = true
                        break
                    }
                }
            }
        }
    }
    

}