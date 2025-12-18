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
    
    func start() {
        guard eventTap == nil else { return }
        
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
            print("MediaKeyManager: Failed to create event tap. Check Accessibility permissions.")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
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
