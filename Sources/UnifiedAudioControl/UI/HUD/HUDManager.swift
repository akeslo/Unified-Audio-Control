import SwiftUI
import AppKit

class HUDManager: ObservableObject {
    static let shared = HUDManager()
    
    private var window: NSWindow?
    private var debouncer: Timer?
    
    @Published var currentType: HUDType = .volume
    @Published var currentValue: Float = 0.5
    @Published var currentDeviceName: String?
    @Published var isVisible: Bool = false
    
    func show(type: HUDType, value: Float, deviceName: String? = nil) {
        // Check preference (default to true)
        let showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        guard showHUD else { return }
        
        DispatchQueue.main.async {
            self.currentType = type
            self.currentValue = value
            self.currentDeviceName = deviceName
            self.isVisible = true
            
            self.ensureWindow()
            self.window?.orderFrontRegardless()
            self.window?.alphaValue = 1.0
            
            self.debouncer?.invalidate()
            self.debouncer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    self?.window?.animator().alphaValue = 0.0
                } completionHandler: {
                    self?.isVisible = false
                    self?.window?.orderOut(nil)
                }
            }
        }
    }
    
    private func ensureWindow() {
        if window == nil {
            let hostHelper = HUDHostView().environmentObject(self)
            
            // Start with a reasonable default, panel will size to content
            let panelWidth: CGFloat = 500
            let panelHeight: CGFloat = 50
            
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .transient]
            
            // Position at bottom center
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let x = screenRect.midX - (panelWidth / 2)
                let y = screenRect.minY + 60
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            } else {
                panel.center()
            }
            
            panel.contentView = NSHostingView(rootView: hostHelper)
            
            self.window = panel
        }
    }
}

struct HUDHostView: View {
    @EnvironmentObject var manager: HUDManager
    
    var body: some View {
        HUDView(type: manager.currentType, value: manager.currentValue, deviceName: manager.currentDeviceName)
            .opacity(manager.isVisible ? 1 : 0)
    }
}
