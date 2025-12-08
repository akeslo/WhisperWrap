import SwiftUI
import AppKit

class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()
    
    private let hudState = HUDState()
    var closeHandler: (() -> Void)?
    
    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true // Make draggable
        
        super.init(window: panel)
        
        // Initialize view once with close handler
        let hudView = HUDView(state: hudState) { [weak self] in
            self?.handleClose()
        }
        let hostingView = NSHostingView(rootView: hudView)
        panel.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show(audioLevel: Float = 0) {
        guard let window = window else { return }
        hudState.startAnimating()
        // Update audio level
        hudState.audioLevel = audioLevel
        
        // Use stored position if available, otherwise default to bottom center
        if let savedPosition = hudState.currentPosition {
            window.setFrameOrigin(savedPosition)
        } else if let screen = NSScreen.main {
            // Default position: Bottom center, just above Dock
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (window.frame.width / 2)
            let y = screenRect.minY + 50
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.orderFront(nil)
    }
    
    func hide() {
        guard let window = window else { return }
        // Save current position before hiding
        hudState.currentPosition = window.frame.origin
        hudState.stopAnimating()
        window.orderOut(nil)
    }
    
    func updateAudioLevel(_ level: Float) {
        hudState.audioLevel = level
        // We don't need to call show() to re-layout, just updating state diffs the UI
        if !window!.isVisible {
            show(audioLevel: level)
        }
    }
    
    func setStatus(_ status: HUDState.HUDStatus) {
        hudState.status = status
    }
    
    private func handleClose() {
        hide()
        closeHandler?()
    }
}
