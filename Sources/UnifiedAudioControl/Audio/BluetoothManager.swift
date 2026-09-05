import Foundation
import IOBluetooth
import Combine

/// Represents a Bluetooth audio device that can be connected/disconnected
struct BluetoothAudioDevice: Identifiable, Hashable {
    let id: String  // Bluetooth device address
    let name: String
    let isConnected: Bool
    let isPaired: Bool
    
    // Helper to check if this is a headphone/AirPods type device
    var isAudioDevice: Bool {
        // This is determined during filtering in BluetoothManager
        return true
    }
}

/// Manages Bluetooth audio device discovery and connection
class BluetoothManager: ObservableObject {
    @Published var recentDevices: [BluetoothAudioDevice] = []

    // MARK: - Pure decision/matching logic (unit-testable, no IOBluetooth access)

    /// Keywords that identify an audio device by name when service-class inspection is inconclusive.
    static let audioNameKeywords = ["airpods", "beats", "headphone", "earphone", "earbud", "speaker", "audio", "bose", "sony wh", "wf-", "jabra", "jbl"]

    /// True iff a Bluetooth SDP service-class-ID-list description mentions an audio profile
    /// (A2DP/AVRCP/Headset/Handsfree/Audio Sink/Source all fall in the 0x110x/0x111x range).
    static func serviceClassIndicatesAudio(_ description: String) -> Bool {
        description.contains("110") || description.contains("111")
    }

    /// True iff a device's advertised name matches a known audio-device keyword (case-insensitive).
    static func nameIndicatesAudioDevice(_ name: String) -> Bool {
        let lower = name.lowercased()
        return audioNameKeywords.contains { lower.contains($0) }
    }

    /// A Bluetooth class-of-device's major class is Audio/Video (0x04) when bits 8-12 equal 0x04.
    static func isAudioVideoMajorClass(_ deviceClass: UInt32) -> Bool {
        let majorClass = (deviceClass >> 8) & 0x1F
        return majorClass == 0x04
    }

    /// Include a device if it's currently connected, or was connected within the recent window.
    static func shouldIncludeDevice(isConnected: Bool, lastConnectionDate: Date?, now: Date = Date(), recentWindow: TimeInterval = 3 * 24 * 3600) -> Bool {
        if isConnected { return true }
        guard let date = lastConnectionDate else { return false }
        return now.timeIntervalSince(date) < recentWindow
    }

    /// Resolves the display name: live name while connected (freshest), else the last-stored alias.
    static func resolveDisplayName(isConnected: Bool, currentName: String?, storedName: String?) -> String {
        if isConnected {
            return currentName ?? "Unknown Device"
        }
        return storedName ?? currentName ?? "Unknown Device"
    }

    /// Sorts devices alphabetically by name (case-insensitive).
    static func sortedByName(_ devices: [BluetoothAudioDevice]) -> [BluetoothAudioDevice] {
        devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var refreshTimer: Timer?
    
    init() {
        refreshDevices()
        
        // Refresh periodically to catch connection state changes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    /// Keys for UserDefaults
    private let kConnectionHistoryKey = "BluetoothDeviceConnectionHistory"
    private let kDeviceNamesKey = "BluetoothDeviceNames"
    
    /// Callback for connection failures
    var onConnectionFailed: (() -> Void)?

    /// Callback for disconnection failures
    var onDisconnectionFailed: (() -> Void)?
    
    /// Refreshes the list of paired Bluetooth audio devices
    func refreshDevices() {
        var devices: [BluetoothAudioDevice] = []
        
        // Get all paired devices
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            DispatchQueue.main.async {
                self.recentDevices = []
            }
            return
        }
        
        // Load connection history and names
        var connectionHistory = UserDefaults.standard.dictionary(forKey: kConnectionHistoryKey) as? [String: Date] ?? [:]
        var deviceNames = UserDefaults.standard.dictionary(forKey: kDeviceNamesKey) as? [String: String] ?? [:]
        
        var historyChanged = false
        var namesChanged = false
        
        for device in pairedDevices {
            let address = device.addressString ?? ""
            let isConnected = device.isConnected()
            
            // Update connection history and name if currently connected
            if isConnected {
                connectionHistory[address] = Date()
                historyChanged = true
                
                // Save the current name (which should be the user-assigned alias)
                if let name = device.name {
                    deviceNames[address] = name
                    namesChanged = true
                }
            }
            
            // Check if this is an audio device by looking at device class
            // Audio devices have specific class bits set:
            // Major class 0x04 = Audio/Video
            // Minor classes include headphones, speakers, etc.
            let deviceClass = device.classOfDevice

            // Major class 0x04 = Audio/Video devices
            // Also check for hands-free (0x02 with minor 0x04) and headset profiles
            let isAudioVideoDevice = BluetoothManager.isAudioVideoMajorClass(UInt32(deviceClass))
            
            // Include devices that have audio-related services
            let hasAudioService = deviceHasAudioServices(device)
            
            if isAudioVideoDevice || hasAudioService {
                // FILTERING LOGIC:
                // Include if:
                // 1. Currently connected
                // 2. Connected within last 3 days
                
                let lastConnectionDate = connectionHistory[address]

                let shouldInclude = BluetoothManager.shouldIncludeDevice(isConnected: isConnected, lastConnectionDate: lastConnectionDate)

                if shouldInclude {
                    // Use stored name if disconnected to preserve alias
                    // Use current name if connected (most up to date)
                    let displayName = BluetoothManager.resolveDisplayName(isConnected: isConnected, currentName: device.name, storedName: deviceNames[address])

                    let btDevice = BluetoothAudioDevice(
                        id: address,
                        name: displayName,
                        isConnected: isConnected,
                        isPaired: device.isPaired()
                    )
                    devices.append(btDevice)
                }
            }
        }
        
        // Save updated history if needed
        if historyChanged {
            UserDefaults.standard.set(connectionHistory, forKey: kConnectionHistoryKey)
        }
        
        // Save updated names if needed
        if namesChanged {
            UserDefaults.standard.set(deviceNames, forKey: kDeviceNamesKey)
        }
        
        // Sort by name
        devices = BluetoothManager.sortedByName(devices)

        DispatchQueue.main.async {
            // Only update if changed to avoid unnecessary redraws
            if devices != self.recentDevices {
                self.recentDevices = devices
            }
        }
    }
    
    /// Check if device has audio-related Bluetooth services
    private func deviceHasAudioServices(_ device: IOBluetoothDevice) -> Bool {
        guard let services = device.services as? [IOBluetoothSDPServiceRecord] else {
            return false
        }
        
        for service in services {
            // Check service class IDs for audio profiles:
            // - A2DP (Advanced Audio Distribution Profile) - 0x110D
            // - AVRCP (Audio/Video Remote Control) - 0x110E
            // - Headset - 0x1108
            // - Handsfree - 0x111E
            // - Audio Sink - 0x110B
            // - Audio Source - 0x110A
            guard let attributes = service.attributes as? [String: Any] else {
                continue
            }
            
            // Look for audio UUIDs in service class ID list
            if let serviceClassIDList = attributes["0001"] { // Service Class ID List
                let description = String(describing: serviceClassIDList)
                // Check for common audio service UUIDs (A2DP/AVRCP/Headset/Handsfree profiles)
                if BluetoothManager.serviceClassIndicatesAudio(description) {
                    return true
                }
            }
        }

        // Fallback: Check device name for common audio device patterns
        return BluetoothManager.nameIndicatesAudioDevice(device.name ?? "")
    }
    
    /// Attempts to connect to a Bluetooth device
    func connect(device: BluetoothAudioDevice) {
        guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
            // Same silent-failure shape as the openConnection() failure path below:
            // printing alone left the UI showing no feedback at all when the device
            // couldn't even be resolved, which is worse than a failed connect attempt.
            NSLog("BluetoothManager: Could not find device with address \(device.id)")
            onConnectionFailed?()
            return
        }
        
        let isAlreadyConnected = btDevice.isConnected()
        
        if isAlreadyConnected {
            NSLog("BluetoothManager: Device \(device.name) is already connected. Forcing reconnection to seize audio...")
            // Force disconnect first to trigger audio handover on reconnect
            btDevice.closeConnection()
            
            // Wait briefly before reconnecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.performConnection(btDevice: btDevice, name: device.name)
            }
        } else {
            // Standard connection
            performConnection(btDevice: btDevice, name: device.name)
        }
    }
    
    private func performConnection(btDevice: IOBluetoothDevice, name: String) {
        // Run connection attempt on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            NSLog("BluetoothManager: Initiating connection to \(name) in background...")

            // Open connection to the device
            // This triggers the macOS Bluetooth system to attempt connection
            // This call can block for several seconds
            let result = btDevice.openConnection()

            DispatchQueue.main.async {
                if result == kIOReturnSuccess {
                    NSLog("BluetoothManager: Connection initiated to \(name)")

                    // Refresh devices after a short delay to update UI
                    // We wait a bit longer to ensure the system registers the state change
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.refreshDevices()
                    }
                } else {
                    NSLog("BluetoothManager: Failed to connect to \(name), error: \(result)")
                    self?.onConnectionFailed?()
                }
            }
        }
    }
    
    /// Disconnects from a Bluetooth device
    func disconnect(device: BluetoothAudioDevice) {
        guard let btDevice = IOBluetoothDevice(addressString: device.id) else {
            NSLog("BluetoothManager: Could not find device with address \(device.id)")
            onDisconnectionFailed?()
            return
        }
        
        let result = btDevice.closeConnection()
        
        if result == kIOReturnSuccess {
            NSLog("BluetoothManager: Disconnected from \(device.name)")
            
            // Refresh devices after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshDevices()
            }
        } else {
            // Same silent-failure shape connect() already guards against via
            // onConnectionFailed: printing to the console is invisible to the user,
            // so a failed disconnect looked identical to a successful one in the UI.
            NSLog("BluetoothManager: Failed to disconnect from \(device.name), error: \(result)")
            onDisconnectionFailed?()
        }
    }
    
    /// Returns disconnected paired audio devices (for "Recent" section)
    var disconnectedDevices: [BluetoothAudioDevice] {
        recentDevices.filter { !$0.isConnected && $0.isPaired }
    }
    
    /// Returns connected paired audio devices (might not be active output)
    var connectedDevices: [BluetoothAudioDevice] {
        recentDevices.filter { $0.isConnected && $0.isPaired }
    }
}
