import Foundation
import Carbon
import AppKit

class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()
    
    @Published var isRecording = false
    @Published var currentHotKey: (keyCode: Int, modifiers: Int)?
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    
    var toggleHandler: (() -> Void)?
    
    init() {
        loadHotKey()
    }
    
    func register(keyCode: Int, modifiers: Int) {
        unregister()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5541434C) // 'UACL' - Unified Audio Control
        hotKeyID.id = 1
        
        var carbonModifiers: UInt32 = 0
        if (modifiers & Int(NSEvent.ModifierFlags.command.rawValue)) != 0 { carbonModifiers |= UInt32(cmdKey) }
        if (modifiers & Int(NSEvent.ModifierFlags.option.rawValue)) != 0 { carbonModifiers |= UInt32(optionKey) }
        if (modifiers & Int(NSEvent.ModifierFlags.control.rawValue)) != 0 { carbonModifiers |= UInt32(controlKey) }
        if (modifiers & Int(NSEvent.ModifierFlags.shift.rawValue)) != 0 { carbonModifiers |= UInt32(shiftKey) }
        
        let status = RegisterEventHotKey(UInt32(keyCode), carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        if status == noErr {
            installEventHandler()
            currentHotKey = (keyCode, modifiers)
            saveHotKey(keyCode: keyCode, modifiers: modifiers)
        } else {
            print("Failed to register hotkey: \(status)")
        }
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        // Don't remove event handler as we might want to register again
    }
    
    private func installEventHandler() {
        guard eventHandler == nil else { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { _, _, _ in
            HotKeyManager.shared.toggleHandler?()
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandler)
    }
    
    private func saveHotKey(keyCode: Int, modifiers: Int) {
        UserDefaults.standard.set(keyCode, forKey: "globalHotKeyKeyCode")
        UserDefaults.standard.set(modifiers, forKey: "globalHotKeyModifiers")
    }
    
    private func loadHotKey() {
        let keyCode = UserDefaults.standard.integer(forKey: "globalHotKeyKeyCode")
        let modifiers = UserDefaults.standard.integer(forKey: "globalHotKeyModifiers")
        
        if keyCode != 0 {
            register(keyCode: keyCode, modifiers: modifiers)
        }
    }
    
    func keyString(keyCode: Int, modifiers: Int) -> String {
        var string = ""
        
        if (modifiers & Int(NSEvent.ModifierFlags.control.rawValue)) != 0 { string += "⌃" }
        if (modifiers & Int(NSEvent.ModifierFlags.option.rawValue)) != 0 { string += "⌥" }
        if (modifiers & Int(NSEvent.ModifierFlags.shift.rawValue)) != 0 { string += "⇧" }
        if (modifiers & Int(NSEvent.ModifierFlags.command.rawValue)) != 0 { string += "⌘" }
        
        // Simple mapping for common keys, incomplete but sufficient for demo
        // A robust solution would use TISCopyCurrentKeyboardLayoutInputSource etc.
        switch keyCode {
        case kVK_ANSI_A: string += "A"
        case kVK_ANSI_B: string += "B"
        case kVK_ANSI_C: string += "C"
        case kVK_ANSI_D: string += "D"
        case kVK_ANSI_E: string += "E"
        case kVK_ANSI_F: string += "F"
        case kVK_ANSI_G: string += "G"
        case kVK_ANSI_H: string += "H"
        case kVK_ANSI_I: string += "I"
        case kVK_ANSI_J: string += "J"
        case kVK_ANSI_K: string += "K"
        case kVK_ANSI_L: string += "L"
        case kVK_ANSI_M: string += "M"
        case kVK_ANSI_N: string += "N"
        case kVK_ANSI_O: string += "O"
        case kVK_ANSI_P: string += "P"
        case kVK_ANSI_Q: string += "Q"
        case kVK_ANSI_R: string += "R"
        case kVK_ANSI_S: string += "S"
        case kVK_ANSI_T: string += "T"
        case kVK_ANSI_U: string += "U"
        case kVK_ANSI_V: string += "V"
        case kVK_ANSI_W: string += "W"
        case kVK_ANSI_X: string += "X"
        case kVK_ANSI_Y: string += "Y"
        case kVK_ANSI_Z: string += "Z"
        case kVK_ANSI_0: string += "0"
        case kVK_ANSI_1: string += "1"
        case kVK_ANSI_2: string += "2"
        case kVK_ANSI_3: string += "3"
        case kVK_ANSI_4: string += "4"
        case kVK_ANSI_5: string += "5"
        case kVK_ANSI_6: string += "6"
        case kVK_ANSI_7: string += "7"
        case kVK_ANSI_8: string += "8"
        case kVK_ANSI_9: string += "9"
        case kVK_Space: string += "Space"
        default: string += "?"
        }
        
        return string
    }
}
