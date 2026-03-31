import SwiftUI
import Combine

@MainActor
class HUDState: ObservableObject {
    enum HUDStatus {
        case listening
        case transcribing
        case selectingPrompt
        case processingWithClaude
    }

    @Published var audioLevel: Float = 0.0
    @Published var streamingText: String = ""
    @Published var phase: Double = 0.0
    @Published var tick: Int = 0
    @Published var status: HUDStatus = .listening

    // Prompt selection state
    @Published var availablePrompts: [ClaudePrompt] = []
    @Published var defaultPromptID: UUID? = nil
    @Published var countdownProgress: Double = 1.0
    @Published var isEnteringCustomPrompt: Bool = false
    @Published var customPromptText: String = ""

    // Audio device selection
    @Published var availableDevices: [(id: String, name: String)] = []
    @Published var selectedDeviceID: String?
    @Published var showingDevicePicker: Bool = false

    // Session-only position (not persisted, resets on app quit)
    var currentPosition: NSPoint?
    
    private var timer: Timer?
    
    func startAnimating() {
        timer?.invalidate()
        // Slower animation (approx 20 fps) for smoother, less frantic look
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // Smaller phase increment for slower wave movement
                self.phase += 0.2
                self.tick += 1
            }
        }
    }
    
    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0.0
        tick = 0
    }
}
