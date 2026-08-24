import SwiftUI
import AppKit
#if compiler(>=6.0)
@preconcurrency import ObjectiveC
#endif

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
    var deviceChangeHandler: ((String) -> Void)?

    private var promptSelectionContinuation: CheckedContinuation<PromptSelectionResult, Never>?
    private var countdownTimer: Timer?

    /// True while the prompt-selection HUD is up and waiting for a choice.
    var isSelectingPrompt: Bool {
        promptSelectionContinuation != nil
    }

    private var clipboardRestoreWorkItem: DispatchWorkItem?
    private var screenChangeObserver: NSObjectProtocol?

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
        // A stray click-drag on the HUD background used to relocate it, and that
        // relocated point became the saved position for every future show() —
        // the HUD isn't meant to be user-repositioned, so it's fixed in place.
        panel.isMovableByWindowBackground = false

        super.init(window: panel)

        // Initialize view once with close handler
        let hudView = HUDView(state: hudState) { [weak self] in
            self?.handleClose()
        }
        let hostingView = NSHostingView(rootView: hudView)
        panel.contentView = hostingView

        // Register for screen configuration changes
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reClampWindowToScreen()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func show(audioLevel: Float = 0) {
        guard let window = window else { return }
        // A pending fade from a previous result would otherwise hide this HUD
        // mid-recording, up to `duration` seconds after the last transcription.
        cancelPendingFade()
        window.alphaValue = 1
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
    
    /// Clears any saved position and snaps the HUD back to its default bottom-center spot.
    func resetPosition() {
        hudState.currentPosition = nil
        guard let window, let screen = NSScreen.screens.first else { return }
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - (window.frame.width / 2)
        let y = screenRect.minY + 50
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        guard let window = window else { return }
        cancelPendingFade()
        // Save current position before hiding
        hudState.currentPosition = window.frame.origin
        hudState.stopAnimating()
        window.orderOut(nil)
    }
    
    func updateAudioLevel(_ level: Float) {
        hudState.audioLevel = level
        // We don't need to call show() to re-layout, just updating state diffs the UI.
        // Called from the 10Hz meter timer, so a nil window after teardown must skip
        // the frame rather than crash the app.
        guard let window else { return }
        if !window.isVisible {
            show(audioLevel: level)
        }
    }
    
    func setStatus(_ status: HUDState.HUDStatus) {
        hudState.status = status
        if status != .listening {
            hudState.showingDevicePicker = false
        }
    }

    func setAudioDevices(_ devices: [(id: String, name: String)], selectedID: String?) {
        hudState.availableDevices = devices
        hudState.selectedDeviceID = selectedID
    }

    func selectDevice(_ deviceID: String) {
        hudState.selectedDeviceID = deviceID
        deviceChangeHandler?(deviceID)
    }

    private var prePickerFrame: NSRect?

    func showDevicePicker() {
        guard let panel = window, let screen = NSScreen.screens.first else { return }
        // Save current position to restore later
        prePickerFrame = panel.frame

        hudState.showingDevicePicker = true

        let rowHeight: CGFloat = 30
        let pickerHeight = CGFloat(hudState.availableDevices.count) * rowHeight + 20
        let newHeight: CGFloat = 80 + pickerHeight
        let newWidth: CGFloat = panel.frame.width

        // Center on screen
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - newWidth / 2
        let y = screenFrame.midY - newHeight / 2
        let centeredFrame = NSRect(x: x, y: y, width: newWidth, height: newHeight)

        resizeWindowOnPrimaryScreen(to: centeredFrame, centerVerticallyIfNeeded: false)
    }

    func hideDevicePicker() {
        guard let panel = window else { return }
        hudState.showingDevicePicker = false

        // Restore to original position
        if let savedFrame = prePickerFrame {
            panel.setFrame(savedFrame, display: true, animate: true)
            prePickerFrame = nil
        } else {
            var frame = panel.frame
            let heightDiff = 80 - frame.height
            frame.size.height = 80
            frame.origin.y -= heightDiff
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    func updateStreamingText(_ text: String) {
        hudState.streamingText = text
        // Resize window to fit content when streaming — only if size actually changes
        if let panel = window {
            let hasText = !text.isEmpty
            let newHeight: CGFloat = hasText ? 280 : 80
            let newWidth: CGFloat = hasText ? 500 : 450
            let currentFrame = panel.frame
            guard abs(currentFrame.size.height - newHeight) > 1 || abs(currentFrame.size.width - newWidth) > 1 else { return }
            let frame = frameKeepingBottomCenter(width: newWidth, height: newHeight)
            resizeWindowOnPrimaryScreen(to: frame, centerVerticallyIfNeeded: true)
        }
    }

    func clearStreamingText(animated: Bool = true) {
        hudState.streamingText = ""
        // Reset window size to prevent off-screen drift
        if window != nil {
            let frame = frameKeepingBottomCenter(width: 450, height: 80)
            resizeWindowOnPrimaryScreen(to: frame, centerVerticallyIfNeeded: true)
        }
    }

    /// Show results for a duration then fade out and hide
    func showResultsThenFade(duration: TimeInterval = 15.0, fadeDuration: TimeInterval = 1.0) {
        guard let panel = window else { return }
        // Switch to results display state so the text stays visible
        hudState.status = .showingResults
        // Cancel any pending fade timer
        cancelPendingFade()

        // Expand height to fit copy footer
        let targetHeight: CGFloat = 315
        if abs(panel.frame.size.height - targetHeight) > 1 {
            let frame = frameKeepingBottomCenter(width: panel.frame.width, height: targetHeight)
            resizeWindowOnPrimaryScreen(to: frame, centerVerticallyIfNeeded: true)
        }

        fadeTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let panel = self.window else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = fadeDuration
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self = self else { return }
                        self.clearStreamingText(animated: false)
                        self.hide()
                        panel.alphaValue = 1 // Reset for next show
                    }
                })
            }
        }
    }

    private var fadeTimer: Timer?

    private func cancelPendingFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
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
        if window != nil {
            let frame = frameKeepingBottomCenter(width: 550, height: 130)
            resizeWindowOnPrimaryScreen(to: frame, centerVerticallyIfNeeded: true)
        }

        return await withCheckedContinuation { continuation in
            // A prompt selection already in flight (rapid stop/start) would
            // otherwise have its continuation dropped here and hang forever.
            if let pending = self.promptSelectionContinuation {
                self.promptSelectionContinuation = nil
                pending.resume(returning: .cancelled)
            }
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

    /// Seconds the prompt-picker HUD waits before auto-selecting the default prompt.
    /// Configurable via Settings; persisted so the picker and the settings UI stay in sync.
    static var promptPickerCountdownDuration: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: "promptPickerCountdownDuration")
            return stored > 0 ? stored : 5.0
        }
        set { UserDefaults.standard.set(newValue, forKey: "promptPickerCountdownDuration") }
    }

    private func startCountdown() {
        let totalDuration: Double = Self.promptPickerCountdownDuration
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
                    // Auto-select default prompt. If the saved default no longer
                    // exists (deleted or stale ID) we must still resume the
                    // continuation, otherwise showPromptSelection() awaits
                    // forever and the HUD sticks in .selectingPrompt.
                    let defaultPrompt = self.hudState.availablePrompts.first(where: { $0.id == self.hudState.defaultPromptID })
                    let continuation = self.promptSelectionContinuation
                    self.promptSelectionContinuation = nil
                    self.resetPromptSelectionSize()
                    if let defaultPrompt {
                        continuation?.resume(returning: .selected(defaultPrompt))
                    } else {
                        continuation?.resume(returning: .skipped)
                    }
                }
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    /// Unified helper to resize window on the primary screen with automatic clamping.
    /// - Parameters:
    ///   - targetFrame: The desired frame for the window.
    ///   - centerVerticallyIfNeeded: If true, centers the frame vertically on the primary screen if it doesn't fit.
    private func resizeWindowOnPrimaryScreen(to targetFrame: NSRect, centerVerticallyIfNeeded: Bool) {
        guard let panel = window, let screen = NSScreen.screens.first else { return }
        var frame = targetFrame
        let screenRect = screen.visibleFrame

        // If requested and frame doesn't fit vertically, center it
        if centerVerticallyIfNeeded && frame.size.height > screenRect.height {
            let centerY = screenRect.midY - frame.size.height / 2
            frame.origin.y = centerY
        } else {
            // Clamp to screen bounds with 10px margin
            if frame.origin.y < screenRect.minY {
                frame.origin.y = screenRect.minY + 10
            }
            if frame.origin.y + frame.size.height > screenRect.maxY {
                frame.origin.y = screenRect.maxY - frame.size.height - 10
            }
        }

        panel.setFrame(frame, display: true, animate: true)
    }

    /// Keeps a candidate frame's vertical extent within the primary screen.
    /// Always uses the same screen (`show()` positions against the primary screen too) so
    /// resize calls don't fight each other across monitors and cause the panel to drift.
    private func clampToScreen(_ frame: inout NSRect, for panel: NSWindow) {
        guard let screen = NSScreen.screens.first ?? panel.screen ?? NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        if frame.origin.y < screenRect.minY {
            frame.origin.y = screenRect.minY + 10
        }
        if frame.origin.y + frame.size.height > screenRect.maxY {
            frame.origin.y = screenRect.maxY - frame.size.height - 10
        }
    }

    /// Re-clamp the window to the primary screen if monitor configuration changes.
    private func reClampWindowToScreen() {
        guard let panel = window else { return }
        var frame = panel.frame
        clampToScreen(&frame, for: panel)
        panel.setFrame(frame, display: true, animate: false)
    }

    private func resetPromptSelectionSize() {
        if window != nil {
            let frame = frameKeepingBottomCenter(width: 450, height: 80)
            resizeWindowOnPrimaryScreen(to: frame, centerVerticallyIfNeeded: true)
        }
    }

    /// Computes a frame of the given size anchored to the window's current bottom-center point.
    /// All in-place HUD resizes (streaming text, results, prompt picker) route through this so
    /// growing and shrinking are exact inverses of each other — no per-callsite delta math that
    /// can disagree between callsites and let the HUD walk across the screen over a session.
    private func frameKeepingBottomCenter(width: CGFloat, height: CGFloat) -> NSRect {
        guard let panel = window else { return NSRect(x: 0, y: 0, width: width, height: height) }
        let current = panel.frame
        let x = current.midX - width / 2
        let y = current.minY
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Clipboard

    /// Copies `text` to the clipboard, snapshotting whatever was there before so it can be
    /// restored 30s later — unless the clipboard was changed by something else in the meantime.
    func copyToClipboardWithRestore(_ text: String) {
        let pasteboard = NSPasteboard.general

        let previousItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let clone = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    clone.setData(data, forType: type)
                }
            }
            return clone
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCountAfterCopy = pasteboard.changeCount

        clipboardRestoreWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == changeCountAfterCopy else { return }
            pasteboard.clearContents()
            if !previousItems.isEmpty {
                pasteboard.writeObjects(previousItems)
            }
        }
        clipboardRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: workItem)
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
