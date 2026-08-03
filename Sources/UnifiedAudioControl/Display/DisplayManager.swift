import Foundation
import CoreGraphics
import DDCSupport

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let uuid: String
    var brightness: Float = 1.0
    var volume: Float = 0.5
    var canControlVolume: Bool = false
    var isBuiltIn: Bool = false
}

class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var allDisplays: [DisplayInfo] = []
    
    var ignoredDisplayUUIDs: Set<String> {
        get {
            let string = UserDefaults.standard.string(forKey: "ignoredDisplayUUIDs") ?? ""
            let ids = string.split(separator: ",").map { String($0) }
            return Set(ids)
        }
        set {
            let string = newValue.joined(separator: ",")
            UserDefaults.standard.set(string, forKey: "ignoredDisplayUUIDs")
            refreshDisplays()
        }
    }
    
    var customNames: [String: String] {
        get {
            return UserDefaults.standard.dictionary(forKey: "customDisplayNames") as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "customDisplayNames")
            refreshDisplays()
        }
    }

    // MARK: - Pure Logic Functions (testable without hardware access)

    /// Resolve the display name, preferring custom name over system name.
    /// Extracted for unit testing (no CoreGraphics dependency).
    static func resolveDisplayName(customNames: [String: String], uuid: String, systemName: String) -> String {
        return customNames[uuid] ?? systemName
    }

    /// Update the set of ignored display UUIDs based on visibility toggle.
    /// Extracted for unit testing.
    static func toggledIgnoredDisplayUUIDs(_ current: [String], uuid: String, visible: Bool) -> [String] {
        var updated = Set(current)
        if visible {
            updated.remove(uuid)
        } else {
            updated.insert(uuid)
        }
        return Array(updated)
    }

    /// Update custom display names when user renames a display.
    /// Extracted for unit testing.
    static func toggledCustomDisplayNames(_ current: [String: String], uuid: String, newName: String) -> [String: String] {
        var updated = current
        if newName.isEmpty {
            updated.removeValue(forKey: uuid)
        } else {
            updated[uuid] = newName
        }
        return updated
    }

    /// Filter and sort displays by visibility and name.
    /// Extracted for unit testing (no CoreGraphics dependency).
    static func sortedVisibleDisplays(_ displays: [DisplayInfo], ignoredUUIDs: [String]) -> [DisplayInfo] {
        let ignored = Set(ignoredUUIDs)
        return displays
            .filter { !ignored.contains($0.uuid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Convert a raw DDC (current, max) pair into a 0...1 fraction.
    ///
    /// Returns nil when the pair cannot describe a fraction — a max of 0 is the one
    /// that actually happens, since a flaky HDMI/DP DDC channel answers a read with
    /// zeroes rather than failing outright. Dividing by it produced NaN (0/0) or +Inf,
    /// which was stored straight into `DisplayInfo.brightness`, handed to the SwiftUI
    /// Slider binding, and fed back into `UInt16(value * 100)` — and `UInt16(NaN)` is
    /// an unconditional runtime trap, so a single bad DDC read crashed the app.
    /// "Cannot tell" is made representable here so the caller falls back explicitly.
    /// Extracted for unit testing (no CoreGraphics dependency).
    static func ddcFraction(current: UInt16, max: UInt16) -> Float? {
        guard max > 0 else { return nil }
        let fraction = Float(current) / Float(max)
        guard fraction.isFinite else { return nil }
        return min(Swift.max(fraction, 0.0), 1.0)
    }

    /// Convert a 0...1 fraction into the 0...100 integer a DDC write expects.
    ///
    /// Clamps rather than trusting the caller: `UInt16(value * 100)` traps on NaN and
    /// on anything negative or above 65535, and the value arrives from a Slider
    /// binding whose backing store can hold a non-finite DDC read.
    /// Extracted for unit testing (no CoreGraphics dependency).
    static func ddcPercent(fromFraction value: Float) -> UInt16 {
        // NaN has no position on the scale, so it cannot be clamped into one — it is
        // rejected outright. Infinities do have a direction, so they clamp normally.
        guard !value.isNaN else { return 0 }
        if value <= 0 { return 0 }
        if value >= 1 { return 100 }
        return UInt16(value * 100)
    }

    func setVisibility(uuid: String, visible: Bool) {
        print("DEBUG: setVisibility uuid=\(uuid) visible=\(visible)")
        var ignored = Array(ignoredDisplayUUIDs)
        ignored = Self.toggledIgnoredDisplayUUIDs(ignored, uuid: uuid, visible: visible)
        print("DEBUG: New ignored list: \(ignored)")
        self.ignoredDisplayUUIDs = Set(ignored)
    }
    
    private var intelDDCs: [CGDirectDisplayID: IntelDDC] = [:]
    private var arm64Services: [CGDirectDisplayID: IOAVService] = [:]
    private let accessQueue = DispatchQueue(label: "com.unifiedaudiocontrol.displaymanager.access")
    
    init() {
        refreshDisplays()
    }
    
    func refreshDisplays() {
        var newDisplays: [DisplayInfo] = []
        
        // Get all displays
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        CGGetActiveDisplayList(16, &activeDisplays, &displayCount)
        
        let activeDisplayIDs = Array(activeDisplays.prefix(Int(displayCount)))
        
        // Batch setup DDC for Arm64
        if Arm64DDC.isArm64 {
            accessQueue.sync {
                arm64Services.removeAll()
            }
            let matches = Arm64DDC.getServiceMatches(displayIDs: activeDisplayIDs)
            accessQueue.sync {
                for match in matches {
                    if let service = match.service {
                        arm64Services[match.displayID] = service
                    }
                }
            }
        }
        
        for displayID in activeDisplayIDs {
            let systemName = getDisplayName(displayID: displayID)
            let uuid = getDisplayUUID(displayID: displayID)
            let name = self.customNames[uuid] ?? systemName
            
            // Setup DDC (Intel fallback)
            if !Arm64DDC.isArm64 {
                setupDDC(for: displayID)
            }
            
            // Initial values (placeholder)
            var brightness: Float = 0.5
            let volume: Float = 0.5
            let canControlVolume = !isAppleDisplay(displayID: displayID)
            
            if isAppleDisplay(displayID: displayID) {
                var appleBrightness: Float = 0.0
                DisplayServicesGetBrightness(displayID, &appleBrightness)
                brightness = appleBrightness
            }
            
            newDisplays.append(DisplayInfo(
                id: displayID,
                name: name,
                uuid: uuid,
                brightness: brightness,
                volume: volume,
                canControlVolume: canControlVolume,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            ))
            
            // Async fetch actual values if not Apple display
            if !isAppleDisplay(displayID: displayID) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let fetchedBrightness = self.getBrightness(displayID: displayID)
                    let fetchedVolume = self.getVolume(displayID: displayID)
                    
                    DispatchQueue.main.async {
                        // Update displays array safely
                        if let index = self.displays.firstIndex(where: { $0.id == displayID }) {
                            self.displays[index].brightness = fetchedBrightness
                            if fetchedVolume >= 0 {
                                self.displays[index].volume = fetchedVolume
                            }
                        }
                        
                        // Update allDisplays array safely
                        if let index = self.allDisplays.firstIndex(where: { $0.id == displayID }) {
                            self.allDisplays[index].brightness = fetchedBrightness
                            if fetchedVolume >= 0 {
                                self.allDisplays[index].volume = fetchedVolume
                            }
                        }
                    }
                }
            }
        }
        
        // Sort alphabetically
        newDisplays.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        self.allDisplays = newDisplays
        self.displays = newDisplays.filter { !self.ignoredDisplayUUIDs.contains($0.uuid) }
    }
    
    private func getDisplayName(displayID: CGDirectDisplayID) -> String {
        if let dict = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as? [String: Any],
           let names = dict["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value {
            return name
        }
        return "Display \(displayID)"
    }
    
    private func getDisplayUUID(displayID: CGDirectDisplayID) -> String {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            print("DEBUG: Could not get UUID for display \(displayID)")
            return ""
        }
        let uuid = unmanaged.takeRetainedValue()
        let uuidString = CFUUIDCreateString(nil, uuid) as String
        print("DEBUG: Display \(displayID) -> UUID \(uuidString)")
        return uuidString
    }
    
    private func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
        // Check if built-in or Apple vendor
        if CGDisplayIsBuiltin(displayID) != 0 { return true }
        
        // Check vendor ID (Apple is 0x610)
        if let dict = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as? [String: Any],
           let vendorID = dict["DisplayVendorID"] as? Int {
            return vendorID == 0x610
        }
        return false
    }
    
    private func setupDDC(for displayID: CGDirectDisplayID) {
        if isAppleDisplay(displayID: displayID) { return }
        
        if !Arm64DDC.isArm64 {
            if let ddc = IntelDDC(for: displayID) {
                accessQueue.sync {
                    intelDDCs[displayID] = ddc
                }
            }
        }
    }
    
    func setCustomName(displayID: CGDirectDisplayID, name: String) {
        let uuid = getDisplayUUID(displayID: displayID)
        guard !uuid.isEmpty else { return }
        
        var names = self.customNames
        if name.isEmpty {
            names.removeValue(forKey: uuid)
        } else {
            names[uuid] = name
        }
        self.customNames = names
    }
    
    func setBrightness(displayID: CGDirectDisplayID, value: Float) {

        if isAppleDisplay(displayID: displayID) {

            DisplayServicesSetBrightness(displayID, value)
        } else {

            let ddcValue = Self.ddcPercent(fromFraction: value)
            writeDDC(displayID: displayID, command: 0x10, value: ddcValue)
        }
        
        if let index = displays.firstIndex(where: { $0.id == displayID }) {
            displays[index].brightness = value
        }
        
        HUDManager.shared.show(type: .brightness, value: value)
    }
    
    func getBrightness(displayID: CGDirectDisplayID) -> Float {
        if isAppleDisplay(displayID: displayID) {
            var brightness: Float = 0.0
            DisplayServicesGetBrightness(displayID, &brightness)
            return brightness
        }
        
        if let (current, max) = readDDC(displayID: displayID, command: 0x10),
           let fraction = Self.ddcFraction(current: current, max: max) {
            return fraction
        }
        return 0.5
    }
    
    func setVolume(displayID: CGDirectDisplayID, value: Float) {
        let ddcValue = Self.ddcPercent(fromFraction: value)
        writeDDC(displayID: displayID, command: 0x62, value: ddcValue)
        
        if let index = displays.firstIndex(where: { $0.id == displayID }) {
            displays[index].volume = value
        }
    }
    
    func getVolume(displayID: CGDirectDisplayID) -> Float {
        if let (current, max) = readDDC(displayID: displayID, command: 0x62),
           let fraction = Self.ddcFraction(current: current, max: max) {
            return fraction
        }
        return -1.0 // Indicate failure
    }
    
    // Debouncing queues and storage
    private let writeDDCQueue = DispatchQueue(label: "com.unifiedaudiocontrol.ddc.write")
    private var writeDDCNextValue: [CGDirectDisplayID: UInt16] = [:]
    private var writeDDCLastSavedValue: [CGDirectDisplayID: UInt16] = [:]
    
    private func writeDDC(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) {
        // Debounce: publish the next value to be written *before* waking the worker.
        // This store used to be `async(flags: .barrier)`, which let the worker's own
        // `writeDDCQueue.sync` win the race and read the previous value — at which
        // point `guard value != lastValue` returned early and the user's newest slider
        // position was never sent to the monitor, so the slider snapped back on the
        // next refresh. The worker must not be able to observe a stale value it was
        // dispatched specifically to write.
        writeDDCQueue.sync(flags: .barrier) {
            self.writeDDCNextValue[displayID] = value
        }

        // Trigger the write asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            self.asyncPerformWriteDDCValues(displayID: displayID, command: command)
        }
    }
    
    private func asyncPerformWriteDDCValues(displayID: CGDirectDisplayID, command: UInt8) {
        var value = UInt16.max
        var lastValue = UInt16.max
        
        // Get the latest value to write
        writeDDCQueue.sync {
            value = self.writeDDCNextValue[displayID] ?? UInt16.max
            lastValue = self.writeDDCLastSavedValue[displayID] ?? UInt16.max
        }
        
        // If nothing to write or value hasn't changed, exit
        guard value != UInt16.max, value != lastValue else {
            return
        }
        
        // Update last saved value
        writeDDCQueue.async(flags: .barrier) {
            self.writeDDCLastSavedValue[displayID] = value
        }
        
        // Perform the actual write
        if Arm64DDC.isArm64 {
            var service: IOAVService?
            accessQueue.sync {
                service = arm64Services[displayID]
            }
            if let service = service {
                _ = Arm64DDC.write(service: service, command: command, value: value)
            }
        } else {
            var ddc: IntelDDC?
            accessQueue.sync {
                ddc = intelDDCs[displayID]
            }
            if let ddc = ddc {
                _ = ddc.write(command: command, value: value)
            }
        }
    }
    
    private func readDDC(displayID: CGDirectDisplayID, command: UInt8) -> (UInt16, UInt16)? {
        if Arm64DDC.isArm64 {
            var service: IOAVService?
            accessQueue.sync {
                service = arm64Services[displayID]
            }
            if let service = service, let values = Arm64DDC.read(service: service, command: command) {
                return (values.current, values.max)
            }
        } else {
            var ddc: IntelDDC?
            accessQueue.sync {
                ddc = intelDDCs[displayID]
            }
            if let ddc = ddc, let values = ddc.read(command: command) {
                return (values.0, values.1)
            }
        }
        return nil
    }
}
