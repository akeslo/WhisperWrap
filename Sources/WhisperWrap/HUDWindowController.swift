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
        
        // Always target the primary screen (the one with index 0 / menu bar)
        let primaryScreen = NSScreen.screens.first
        
        // Default position: Bottom center of the primary screen
        var targetOrigin: NSPoint?
        
        if let screen = primaryScreen {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (window.frame.width / 2)
            let y = screenRect.minY + 50
            targetOrigin = NSPoint(x: x, y: y)
        }
        
        // Use stored position ONLY if it is on the primary screen
        if let savedPosition = hudState.currentPosition, let screen = primaryScreen {
            // Check if the saved position is roughly within the primary screen's frame
            if NSPointInRect(savedPosition, screen.frame) {
                targetOrigin = savedPosition
            }
        }
        
        if let origin = targetOrigin {
            window.setFrameOrigin(origin)
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

    func updateStreamingText(_ text: String) {
        hudState.streamingText = text
        // Resize window to fit content when streaming
        if let panel = window {
            let hasText = !text.isEmpty
            let newHeight: CGFloat = hasText ? 280 : 80
            let newWidth: CGFloat = hasText ? 500 : 450
            var frame = panel.frame
            let heightDiff = newHeight - frame.height
            frame.size.height = newHeight
            frame.size.width = newWidth
            frame.origin.y -= heightDiff // Grow upward
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    func clearStreamingText() {
        hudState.streamingText = ""
        // Reset window size
        if let panel = window {
            var frame = panel.frame
            let heightDiff = 80 - frame.height
            frame.size.height = 80
            frame.size.width = 450
            frame.origin.y -= heightDiff
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    private func handleClose() {
        hide()
        closeHandler?()
    }
}
