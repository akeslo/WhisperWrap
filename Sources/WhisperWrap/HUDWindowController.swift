import SwiftUI
import AppKit

/// Floating, non-activating HUD pinned top-center under the menu bar. It is one panel
/// that morphs: a capsule while recording/decoding, then a small Refine pill.
@MainActor
final class HUDWindowController: NSWindowController, NSWindowDelegate {
    static let shared = HUDWindowController()

    static let capsuleSize = NSSize(width: 340, height: 44)
    static let pillSize = NSSize(width: 176, height: 32)
    static let refineOfferSeconds: TimeInterval = 6
    /// User-dragged top-center anchor of the HUD; absent means the default spot.
    static let anchorDefaultsKey = "hudAnchor"
    static let snapDistance: CGFloat = 24

    private let hudState = HUDState()
    var closeHandler: (() -> Void)?
    var deviceChangeHandler: ((String) -> Void)?
    private var onRefine: ((UUID?) -> Void)?
    private var dismissTimer: Timer?
    private var isPlacing = false

    init() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.capsuleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // the SwiftUI capsule draws its own offset shadow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        panel.delegate = self

        let view = HUDView(
            state: hudState,
            onClose: { [weak self] in self?.hide(); self?.closeHandler?() },
            onDevice: { [weak self] id in self?.hudState.selectedDeviceID = id; self?.deviceChangeHandler?(id) },
            onRefine: { [weak self] id in self?.triggerRefine(id) },
            onDismissPill: { [weak self] in self?.hide() }
        )
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Visibility

    func show(audioLevel: Float = 0) {
        cancelDismiss()
        hudState.audioLevel = audioLevel
        if hudState.status == .listening { hudState.recordingStartedAt = Date() }
        place(size: hudState.isPill ? Self.pillSize : Self.capsuleSize, animate: false)
        window?.alphaValue = 1
        window?.orderFront(nil)
    }

    func hide() {
        cancelDismiss()
        onRefine = nil
        hudState.note = ""
        window?.orderOut(nil)
    }

    /// Saved anchor if it is still on a screen, else top-center of the primary screen.
    private var anchor: NSPoint {
        if let a = UserDefaults.standard.array(forKey: Self.anchorDefaultsKey) as? [Double], a.count == 2 {
            let p = NSPoint(x: a[0], y: a[1])
            if NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: p.x, y: p.y - 1)) }) { return p }
        }
        guard let vf = NSScreen.screens.first?.visibleFrame else { return .zero }
        return NSPoint(x: vf.midX, y: vf.maxY - 10)
    }

    /// Forget the dragged position and go back to top-center.
    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.anchorDefaultsKey)
        if let panel = window, panel.isVisible { place(size: panel.frame.size, animate: true) }
    }

    /// Drag ended: snap to screen edges / center lines within snapDistance, then save.
    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, let panel = window,
              let vf = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = panel.frame
        let d = Self.snapDistance
        func snap(_ v: CGFloat, _ targets: [CGFloat]) -> CGFloat {
            targets.first { abs($0 - v) <= d } ?? v
        }
        f.origin.x = snap(f.minX, [vf.minX + 10, vf.midX - f.width / 2, vf.maxX - f.width - 10])
        f.origin.y = snap(f.minY, [vf.minY + 10, vf.midY - f.height / 2, vf.maxY - f.height - 10])
        // Keep it fully on screen.
        f.origin.x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        if f.origin != panel.frame.origin {
            isPlacing = true
            panel.setFrameOrigin(f.origin)
            isPlacing = false
        }
        UserDefaults.standard.set([Double(f.midX), Double(f.maxY)], forKey: Self.anchorDefaultsKey)
    }

    private func place(size: NSSize, animate: Bool) {
        guard let panel = window else { return }
        let a = anchor
        let frame = NSRect(x: a.x - size.width / 2, y: a.y - size.height, width: size.width, height: size.height)
        isPlacing = true
        defer { isPlacing = false }
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - State

    func setStatus(_ status: HUDState.HUDStatus) {
        let wasPill = hudState.isPill
        withAnimation(.snappy(duration: 0.28)) { hudState.status = status }
        if status == .listening { hudState.recordingStartedAt = Date() }
        if wasPill != hudState.isPill, window?.isVisible == true {
            place(size: hudState.isPill ? Self.pillSize : Self.capsuleSize, animate: true)
        }
    }

    func updateAudioLevel(_ level: Float) {
        hudState.audioLevel = level
        if window?.isVisible == false { show(audioLevel: level) }
    }

    func setAudioDevices(_ devices: [(id: String, name: String)], selectedID: String?) {
        hudState.availableDevices = devices
        hudState.selectedDeviceID = selectedID
    }

    func updateStreamingText(_ text: String) { hudState.note = text }
    func clearStreamingText(animated: Bool = true) { hudState.note = "" }

    // MARK: - Refine pill

    func showRefinePill(prompts: [ClaudePrompt], defaultID: UUID, onRefine: @escaping (UUID?) -> Void) {
        hudState.prompts = prompts
        hudState.defaultPromptID = defaultID
        hudState.note = ""
        self.onRefine = onRefine
        if window?.isVisible != true { hudState.status = .refineOffer; show() } else { setStatus(.refineOffer) }
        scheduleDismiss(after: Self.refineOfferSeconds)
    }

    private func triggerRefine(_ promptID: UUID?) {
        cancelDismiss()
        let handler = onRefine
        onRefine = nil
        handler?(promptID)
    }

    /// Refine finished and the text was swapped in.
    func flashLanded() {
        if window?.isVisible != true { hudState.status = .landed; show() } else { setStatus(.landed) }
        scheduleDismiss(after: 1.2)
    }

    func flashFailure(_ message: String) {
        if window?.isVisible != true { hudState.status = .failed(message); show() } else { setStatus(.failed(message)) }
        scheduleDismiss(after: 4)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        cancelDismiss()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.window else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 },
                                                    completionHandler: { Task { @MainActor in self.hide() } })
            }
        }
    }

    private func cancelDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.alphaValue = 1
    }
}
