import Cocoa
import SwiftUI

/// Custom NSHostingView that passes through mouse events in areas outside the notch content.
/// Calculates the notch bounds from the known layout constants instead of relying on
/// GeometryReader coordinate conversions which break across SwiftUI/AppKit coordinate spaces.
class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    
    // Allow clicks to work immediately without needing to activate the window first
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 700
        
        let contentWidth = NotchContentTracker.shared.contentWidth
        let contentHeight = NotchContentTracker.shared.contentHeight
        
        // Content is centered horizontally, anchored to the top of the canvas.
        // In NSView coords (bottom-left origin), the content occupies:
        let minX = (canvasWidth - contentWidth) / 2 - 20
        let maxX = (canvasWidth + contentWidth) / 2 + 20
        let minY = canvasHeight - contentHeight - 20
        let maxY = canvasHeight + 10
        
        let contentRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        
        if !contentRect.contains(point) {
            return nil
        }
        
        return super.hitTest(point)
    }
}

class NotchWindowController: NSWindowController {
    
    convenience init(rootView: ContentView) {
        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 700
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .popUpMenu
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        
        let wrappedView = rootView
            .frame(width: canvasWidth, height: canvasHeight, alignment: .top)
        
        let hostingView = PassthroughHostingView(rootView: wrappedView)
        panel.contentView = hostingView
        
        self.init(window: panel)
        self.positionWindow()
        
        NotificationCenter.default.addObserver(self, selector: #selector(screenDidChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    
    @objc private func screenDidChange(_ notification: Notification) {
        self.positionWindow()
    }
    
    @objc func positionWindow() {
        guard let window = window, let screen = NSScreen.screens.first else { return }
        
        let screenRect = screen.frame
        let originX = screenRect.midX - window.frame.width / 2
        let originY = screenRect.maxY - window.frame.height
        
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

/// Simple tracker for notch content dimensions (set from SwiftUI, read from AppKit)
class NotchContentTracker: ObservableObject {
    static let shared = NotchContentTracker()
    var contentWidth: CGFloat = 320
    var contentHeight: CGFloat = 40
}
