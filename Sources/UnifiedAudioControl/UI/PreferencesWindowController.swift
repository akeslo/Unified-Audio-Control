import Cocoa
import SwiftUI

class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    static let shared = PreferencesWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()
        window.setFrameAutosaveName("Preferences")
        window.isReleasedWhenClosed = false
        window.level = .floating // Keep on top as requested
        
        // Create the SwiftUI view
        let preferencesView = PreferencesView(
            audioManager: MenuBarManager.shared.audioManager,
            displayManager: MenuBarManager.shared.displayManager
        )
        
        // Host it
        let hostingController = NSHostingController(rootView: preferencesView)
        window.contentViewController = hostingController
        
        super.init(window: window)
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        // Ensure window is active and front
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        // Handle any cleanup if needed
    }
}
