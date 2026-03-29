import SwiftUI
import AppKit

enum PromptSelectionResult {
    case selected(ClaudePrompt)
    case custom(String)
    case skipped
    case cancelled
}

class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()

    private let hudState = HUDState()
    var closeHandler: (() -> Void)?

    private var promptSelectionContinuation: CheckedContinuation<PromptSelectionResult, Never>?
    private var countdownTimer: Timer?
    
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

    func clearStreamingText(animated: Bool = true) {
        hudState.streamingText = ""
        // Reset window size
        if let panel = window {
            var frame = panel.frame
            let heightDiff = 80 - frame.height
            frame.size.height = 80
            frame.size.width = 450
            frame.origin.y -= heightDiff
            panel.setFrame(frame, display: true, animate: animated)
        }
    }

    // MARK: - Prompt Selection

    func showPromptSelection(
        prompts: [ClaudePrompt],
        defaultID: UUID
    ) async -> PromptSelectionResult {
        hudState.availablePrompts = prompts
        hudState.defaultPromptID = defaultID
        hudState.countdownProgress = 1.0
        hudState.isEnteringCustomPrompt = false
        hudState.customPromptText = ""
        hudState.status = .selectingPrompt

        // Resize window for prompt selection (wider to fit all buttons)
        if let panel = window {
            var frame = panel.frame
            let newHeight: CGFloat = 130
            let newWidth: CGFloat = 550
            let heightDiff = newHeight - frame.height
            let widthDiff = newWidth - frame.width
            frame.size.height = newHeight
            frame.size.width = newWidth
            frame.origin.y -= heightDiff
            frame.origin.x -= widthDiff / 2 // Keep centered
            panel.setFrame(frame, display: true, animate: true)
        }

        return await withCheckedContinuation { continuation in
            self.promptSelectionContinuation = continuation
            startCountdown()
        }
    }

    func selectPrompt(_ prompt: ClaudePrompt) {
        stopCountdown()
        let continuation = promptSelectionContinuation
        promptSelectionContinuation = nil
        resetPromptSelectionSize()
        continuation?.resume(returning: .selected(prompt))
    }

    func submitCustomPrompt(_ text: String) {
        stopCountdown()
        let continuation = promptSelectionContinuation
        promptSelectionContinuation = nil
        resetPromptSelectionSize()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            continuation?.resume(returning: .cancelled)
        } else {
            continuation?.resume(returning: .custom(text))
        }
    }

    func skipPromptSelection() {
        stopCountdown()
        let continuation = promptSelectionContinuation
        promptSelectionContinuation = nil
        resetPromptSelectionSize()
        continuation?.resume(returning: .skipped)
    }

    func cancelPromptSelection() {
        stopCountdown()
        let continuation = promptSelectionContinuation
        promptSelectionContinuation = nil
        resetPromptSelectionSize()
        continuation?.resume(returning: .cancelled)
    }

    private func startCountdown() {
        let totalDuration: Double = 5.0
        let interval: Double = 0.05
        let decrement = interval / totalDuration

        countdownTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Pause countdown while entering custom prompt
                if self.hudState.isEnteringCustomPrompt { return }

                self.hudState.countdownProgress -= decrement
                if self.hudState.countdownProgress <= 0 {
                    self.hudState.countdownProgress = 0
                    self.stopCountdown()
                    // Auto-select default prompt
                    if let defaultPrompt = self.hudState.availablePrompts.first(where: { $0.id == self.hudState.defaultPromptID }) {
                        let continuation = self.promptSelectionContinuation
                        self.promptSelectionContinuation = nil
                        self.resetPromptSelectionSize()
                        continuation?.resume(returning: .selected(defaultPrompt))
                    }
                }
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private func resetPromptSelectionSize() {
        if let panel = window {
            var frame = panel.frame
            let newHeight: CGFloat = 80
            let newWidth: CGFloat = 450
            let heightDiff = newHeight - frame.height
            let widthDiff = newWidth - frame.width
            frame.size.height = newHeight
            frame.size.width = newWidth
            frame.origin.y -= heightDiff
            frame.origin.x -= widthDiff / 2 // Keep centered
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    private func handleClose() {
        // If we're in prompt selection, cancel it
        if promptSelectionContinuation != nil {
            cancelPromptSelection()
            hide()
            return
        }
        hide()
        closeHandler?()
    }
}
