import Cocoa
import Carbon.HIToolbox

protocol MediaKeyDelegate: AnyObject {
    func onVolumeUp()
    func onVolumeDown()
    func onMute()
}

class MediaKeyManager {
    weak var delegate: MediaKeyDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    init() {}
    
    func start() -> Bool {
        guard eventTap == nil else { return true }

        // Listen for all events to capture system defined ones
        // System defined events have type 14 but we use a broad mask
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue) |
                                     (1 << 14)  // NX_SYSDEFINED

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if let observer = refcon {
                    let manager = Unmanaged<MediaKeyManager>.fromOpaque(observer).takeUnretainedValue()
                    return manager.handle(proxy: proxy, type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("MediaKeyManager: Failed to create event tap. Check Accessibility permissions in System Settings > Privacy & Security.")
            return false
        }

        // Only publish `eventTap` once the tap is actually wired into a run loop.
        // Assigning it first meant a nil run-loop source left a non-nil `eventTap`
        // behind: `start()` returned true (so the caller logged no warning) and every
        // later call short-circuited on the `eventTap == nil` guard above, leaving
        // media keys permanently dead with no way to recover short of a relaunch.
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            NSLog("MediaKeyManager: Failed to create run loop source for the event tap.")
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }
    
    func stop() {
        // Detach the source from the run loop before invalidating the port it was
        // created from — the reverse order leaves the run loop briefly holding a
        // source backed by a dead mach port.
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }
    
    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events - re-enable
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        // We need to convert to NSEvent to properly parse system defined events
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        
        // Only handle system defined events with subtype 8 (media keys)
        guard nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        
        // data1 layout:
        // Bits 0-15: flags (bit 8 = key down/up)
        // Bits 16-23: key code
        // Bits 24-31: reserved
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0x00FF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        
        // Only act on key down
        guard keyDown else {
            // Still consume key up for our media keys to prevent system handling
            if keyCode == Int(NX_KEYTYPE_SOUND_UP) ||
               keyCode == Int(NX_KEYTYPE_SOUND_DOWN) ||
               keyCode == Int(NX_KEYTYPE_MUTE) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        
        switch keyCode {
        case Int(NX_KEYTYPE_SOUND_UP):
            delegate?.onVolumeUp()
            return nil // Consume
            
        case Int(NX_KEYTYPE_SOUND_DOWN):
            delegate?.onVolumeDown()
            return nil // Consume
            
        case Int(NX_KEYTYPE_MUTE):
            delegate?.onMute()
            return nil // Consume
            
        default:
            break
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
