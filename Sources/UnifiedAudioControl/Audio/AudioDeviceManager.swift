import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let systemName: String
    let uid: String
    let isAggregate: Bool
    let transportType: UInt32
    
    // Conformance to Identifiable
    var id_wrapper: Int { Int(id) }
    
    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }
}

class AudioDeviceManager: ObservableObject {
    @Published var outputDevices: [AudioDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published var volume: Float = 0.0
    @Published var isMuted: Bool = false
    @Published var canControlVolume: Bool = false

    // MARK: - Pure decision/matching logic (unit-testable, no CoreAudio access)

    /// Parses the comma-separated ignored-UID persistence format.
    static func parseIgnoredUIDs(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { String($0) })
    }

    /// Toggles a single UID's membership in the ignored set based on desired visibility.
    static func toggledIgnoredUIDs(_ ignored: Set<String>, uid: String, visible: Bool) -> Set<String> {
        var result = ignored
        if visible {
            result.remove(uid)
        } else {
            result.insert(uid)
        }
        return result
    }

    /// Adds/removes a custom name entry for a device UID.
    static func toggledCustomNames(_ names: [String: String], uid: String, newName: String) -> [String: String] {
        var result = names
        if newName.isEmpty {
            result.removeValue(forKey: uid)
        } else {
            result[uid] = newName
        }
        return result
    }

    /// Resolves the display name for a device: custom name if set, else the system-reported name.
    static func resolveDisplayName(customNames: [String: String], uid: String, systemName: String) -> String {
        customNames[uid] ?? systemName
    }

    /// Filters out ignored devices and sorts the remainder alphabetically (case-insensitive).
    static func sortedVisibleDevices(_ devices: [AudioDevice], ignoredUIDs: Set<String>) -> [AudioDevice] {
        devices
            .filter { !ignoredUIDs.contains($0.uid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A CoreAudio stream-list property size is non-zero iff the device exposes streams in that scope.
    static func hasOutputStreams(propertySize: UInt32) -> Bool {
        propertySize > 0
    }

    /// A device is an aggregate device iff its transport type matches the aggregate constant.
    static func isAggregateTransportType(_ transportType: UInt32) -> Bool {
        transportType == kAudioDeviceTransportTypeAggregate
    }

    /// Volume of an aggregate device is the max volume among its output sub-devices (0 if none).
    static func maxVolume(_ volumes: [Float]) -> Float {
        volumes.max() ?? 0.0
    }

    /// An aggregate device can have its volume set if any output sub-device can.
    static func anySettable(_ settableFlags: [Bool]) -> Bool {
        settableFlags.contains(true)
    }

    var ignoredDeviceUIDs: Set<String> {
        get {
            let string = UserDefaults.standard.string(forKey: "ignoredAudioDeviceUIDs") ?? ""
            return AudioDeviceManager.parseIgnoredUIDs(string)
        }
        set {
            let string = newValue.joined(separator: ",")
            UserDefaults.standard.set(string, forKey: "ignoredAudioDeviceUIDs")
            updateCurrentState() // Refresh list
        }
    }
    
    var customNames: [String: String] {
        get {
            return UserDefaults.standard.dictionary(forKey: "customAudioDeviceNames") as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "customAudioDeviceNames")
            refreshDevices()
        }
    }
    
    func setVisibility(uid: String, visible: Bool) {
        self.ignoredDeviceUIDs = AudioDeviceManager.toggledIgnoredUIDs(ignoredDeviceUIDs, uid: uid, visible: visible)
    }
    
    // Keep track of all devices for Preferences
    @Published var allOutputDevices: [AudioDevice] = []
    
    private var systemListenerAdded = false
    
    init() {
        refreshDevices()
        updateCurrentState()
        startSystemListeners()
    }
    
    deinit {
        stopSystemListeners()
    }
    
    func refreshDevices() {
        let newDevices = getOutputDevices()
        // Only update if changed to avoid loops/redraws
        if newDevices != self.outputDevices {
            self.outputDevices = newDevices
        }
    }
    
    func updateCurrentState() {
        let newDefault = getDefaultOutputDevice()
        if newDefault != self.selectedDeviceID {
            self.selectedDeviceID = newDefault
            // Attach listeners to new device
            startDeviceListeners(deviceID: newDefault)
        } else if currentDeviceListenerID == kAudioDeviceUnknown && newDefault != kAudioDeviceUnknown {
             // Ensure listeners are attached if they weren't
             startDeviceListeners(deviceID: newDefault)
        }
        
        if self.selectedDeviceID != kAudioDeviceUnknown {
            self.volume = getDeviceVolume(deviceID: self.selectedDeviceID)
            self.isMuted = isDeviceMuted(deviceID: self.selectedDeviceID)
            self.canControlVolume = checkCanSetVolume(deviceID: self.selectedDeviceID)
        } else {
            self.canControlVolume = false
        }
    }
    
    // MARK: - Listeners
    
    private var currentDeviceListenerID: AudioDeviceID = kAudioDeviceUnknown
    
    private func startSystemListeners() {
        guard !systemListenerAdded else { return }
        
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, propertyListener, selfPtr)
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, propertyListener, selfPtr)
        
        systemListenerAdded = true
    }
    
    private func stopSystemListeners() {
        guard systemListenerAdded else { return }
        
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, propertyListener, selfPtr)
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, propertyListener, selfPtr)
        
        systemListenerAdded = false
        
        // Also stop device listeners
        stopDeviceListeners()
    }
    
    private func startDeviceListeners(deviceID: AudioDeviceID) {
        // print("DEBUG: startDeviceListeners for device \(deviceID)")
        guard deviceID != kAudioDeviceUnknown else { return }
        // Stop previous if any
        if currentDeviceListenerID != kAudioDeviceUnknown {
            stopDeviceListeners()
        }
        
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        // Add listener for Master
        if AudioObjectHasProperty(deviceID, &volumeAddress) {
            AudioObjectAddPropertyListener(deviceID, &volumeAddress, propertyListener, selfPtr)
        }
        
        // Add listener for Channel 1
        volumeAddress.mElement = 1
        if AudioObjectHasProperty(deviceID, &volumeAddress) {
            AudioObjectAddPropertyListener(deviceID, &volumeAddress, propertyListener, selfPtr)
        }
        
        // Add listener for Channel 2
        volumeAddress.mElement = 2
        if AudioObjectHasProperty(deviceID, &volumeAddress) {
            AudioObjectAddPropertyListener(deviceID, &volumeAddress, propertyListener, selfPtr)
        }
        
        AudioObjectAddPropertyListener(deviceID, &muteAddress, propertyListener, selfPtr)
        
        currentDeviceListenerID = deviceID
    }
    
    private func stopDeviceListeners() {
        // print("DEBUG: stopDeviceListeners for device \(currentDeviceListenerID)")
        guard currentDeviceListenerID != kAudioDeviceUnknown else { return }
        
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        // Remove listener for Master
        if AudioObjectHasProperty(currentDeviceListenerID, &volumeAddress) {
            AudioObjectRemovePropertyListener(currentDeviceListenerID, &volumeAddress, propertyListener, selfPtr)
        }
        
        // Remove listener for Channel 1
        volumeAddress.mElement = 1
        if AudioObjectHasProperty(currentDeviceListenerID, &volumeAddress) {
            AudioObjectRemovePropertyListener(currentDeviceListenerID, &volumeAddress, propertyListener, selfPtr)
        }
        
        // Remove listener for Channel 2
        volumeAddress.mElement = 2
        if AudioObjectHasProperty(currentDeviceListenerID, &volumeAddress) {
            AudioObjectRemovePropertyListener(currentDeviceListenerID, &volumeAddress, propertyListener, selfPtr)
        }
        
        AudioObjectRemovePropertyListener(currentDeviceListenerID, &muteAddress, propertyListener, selfPtr)
        
        currentDeviceListenerID = kAudioDeviceUnknown
    }
    
    func handlePropertyChange(selector: AudioObjectPropertySelector) {
        DispatchQueue.main.async {
            switch selector {
            case kAudioHardwarePropertyDevices:
                self.refreshDevices()
            case kAudioHardwarePropertyDefaultOutputDevice:
                self.updateCurrentState()
            case kAudioDevicePropertyVolumeScalar:
                if self.selectedDeviceID != kAudioDeviceUnknown {
                    self.volume = self.getDeviceVolume(deviceID: self.selectedDeviceID)
                }
            case kAudioDevicePropertyMute:
                if self.selectedDeviceID != kAudioDeviceUnknown {
                    self.isMuted = self.isDeviceMuted(deviceID: self.selectedDeviceID)
                }
            default:
                break
            }
        }
    }
    
    private func getOutputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        let allDevices = getAllDevices()
        
        for deviceID in allDevices {
            if isOutputDevice(deviceID: deviceID) {
                let systemName = getDeviceName(deviceID: deviceID)
                let uid = getDeviceUID(deviceID: deviceID)
                let name = AudioDeviceManager.resolveDisplayName(customNames: self.customNames, uid: uid, systemName: systemName)
                let isAgg = isAggregateDevice(deviceID: deviceID)
                let transport = getDeviceTransportType(deviceID: deviceID)
                devices.append(AudioDevice(id: deviceID, name: name, systemName: systemName, uid: uid, isAggregate: isAgg, transportType: transport))
            }
        }

        // Sort alphabetically
        devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Update all devices list
        DispatchQueue.main.async {
            self.allOutputDevices = devices
        }

        // Filter ignored devices
        return AudioDeviceManager.sortedVisibleDevices(devices, ignoredUIDs: self.ignoredDeviceUIDs)
    }
    
    func selectDevice(deviceID: AudioDeviceID) {
        setOutputDevice(newDeviceID: deviceID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateCurrentState()
        }
    }
    
    func setCustomName(deviceID: AudioDeviceID, name: String) {
        let uid = getDeviceUID(deviceID: deviceID)
        guard !uid.isEmpty else { return }

        self.customNames = AudioDeviceManager.toggledCustomNames(self.customNames, uid: uid, newName: name)
    }
    
    func setVolume(_ newVolume: Float) {
        guard selectedDeviceID != kAudioDeviceUnknown else { return }
        setDeviceVolume(deviceID: selectedDeviceID, volume: newVolume)
        self.volume = newVolume
        
        HUDManager.shared.show(type: .volume, value: newVolume)
        
        if newVolume > 0 && isMuted {
            toggleMute()
        }
    }
    
    func toggleMute() {
        guard selectedDeviceID != kAudioDeviceUnknown else { return }
        let newMuteState = !isMuted
        setDeviceMute(deviceID: selectedDeviceID, isMute: newMuteState)
        self.isMuted = newMuteState
        
        // Show 0 volume if muted, else current volume
        HUDManager.shared.show(type: .volume, value: newMuteState ? 0 : volume)
    }
    
    // MARK: - Low Level Core Audio
    
    private func getAllDevices() -> [AudioDeviceID] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        
        let devicesCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: devicesCount)
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &devices)
        
        return devices
    }
    
    private func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
        var propertySize: UInt32 = 256
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        return AudioDeviceManager.hasOutputStreams(propertySize: propertySize)
    }
    
    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &result)
        
        if status == noErr, let result = result {
            return result.takeRetainedValue() as String
        }
        return ""
    }
    
    private func getDeviceUID(deviceID: AudioDeviceID) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &result)
        
        if status == noErr, let result = result {
            return result.takeRetainedValue() as String
        }
        return ""
    }
    
    private func getDefaultOutputDevice() -> AudioDeviceID {
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID = kAudioDeviceUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        return deviceID
    }
    
    private func setOutputDevice(newDeviceID: AudioDeviceID) {
        var deviceID = newDeviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, propertySize, &deviceID)
    }
    
    private func getDeviceVolume(deviceID: AudioDeviceID) -> Float {
        if isAggregateDevice(deviceID: deviceID) {
            let subDevices = getAggregateDeviceSubDeviceList(deviceID: deviceID)
            let volumes = subDevices
                .filter { isOutputDevice(deviceID: $0) }
                .map { getDeviceVolume(deviceID: $0) }
            return AudioDeviceManager.maxVolume(volumes)
        }

        var volume: Float32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if !AudioObjectHasProperty(deviceID, &propertyAddress) {
            // Fallback to channel 1 (Left)
            propertyAddress.mElement = 1
        }
        
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &volume)
        
        if status != noErr {
            return 0.0
        }
        
        return volume
    }
    
    private func checkCanSetVolume(deviceID: AudioDeviceID) -> Bool {
        if isAggregateDevice(deviceID: deviceID) {
            let subDevices = getAggregateDeviceSubDeviceList(deviceID: deviceID)
            let settableFlags = subDevices
                .filter { isOutputDevice(deviceID: $0) }
                .map { checkCanSetVolume(deviceID: $0) }
            return AudioDeviceManager.anySettable(settableFlags)
        }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isSettable: DarwinBoolean = false
        
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            AudioObjectIsPropertySettable(deviceID, &propertyAddress, &isSettable)
            if isSettable.boolValue { return true }
        }
        
        // Check channels
        propertyAddress.mElement = 1
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            AudioObjectIsPropertySettable(deviceID, &propertyAddress, &isSettable)
            if isSettable.boolValue { return true }
        }
        
        return false
    }
    
    private func setDeviceVolume(deviceID: AudioDeviceID, volume: Float) {
        var newVolume = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        
        // Try Master
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if AudioObjectHasProperty(deviceID, &propertyAddress) {
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, size, &newVolume)
        } else {
            // Set for channels 1 and 2
            propertyAddress.mElement = 1
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, size, &newVolume)
            propertyAddress.mElement = 2
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, size, &newVolume)
        }
        
        // Handle Aggregate Devices (Simplified recursion)
        if isAggregateDevice(deviceID: deviceID) {
            let subDevices = getAggregateDeviceSubDeviceList(deviceID: deviceID)
            for subDevice in subDevices {
                setDeviceVolume(deviceID: subDevice, volume: volume)
            }
        }
    }
    
    private func isDeviceMuted(deviceID: AudioDeviceID) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &muted)
        return muted == 1
    }
    
    private func setDeviceMute(deviceID: AudioDeviceID, isMute: Bool) {
        var muted: UInt32 = isMute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, size, &muted)
        
        if isAggregateDevice(deviceID: deviceID) {
            let subDevices = getAggregateDeviceSubDeviceList(deviceID: deviceID)
            for subDevice in subDevices {
                setDeviceMute(deviceID: subDevice, isMute: isMute)
            }
        }
    }
    
    private func isAggregateDevice(deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &transportType)
        return AudioDeviceManager.isAggregateTransportType(transportType)
    }
    
    private func getDeviceTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &transportType)
        return transportType
    }
    
    private func getAggregateDeviceSubDeviceList(deviceID: AudioDeviceID) -> [AudioDeviceID] {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        
        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var subDevices = [AudioDeviceID](repeating: 0, count: count)
        
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &subDevices)
        return subDevices
    }
}

private func propertyListener(objectID: AudioObjectID, numberAddresses: UInt32, addresses: UnsafePointer<AudioObjectPropertyAddress>, clientData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let clientData = clientData else { return noErr }
    let manager = Unmanaged<AudioDeviceManager>.fromOpaque(clientData).takeUnretainedValue()
    
    let addressBuffer = UnsafeBufferPointer(start: addresses, count: Int(numberAddresses))
    for address in addressBuffer {
        manager.handlePropertyChange(selector: address.mSelector)
    }
    
    return noErr
}
