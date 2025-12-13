import SwiftUI

@main
struct UnifiedAudioControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty WindowGroup - app runs from menu bar only
        // Preferences are opened via MenuBarManager
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the menu bar manager
        menuBarManager = MenuBarManager.shared
        
        // Hide the dock icon since this is a menu bar app
        NSApp.setActivationPolicy(.accessory)
    }
}
