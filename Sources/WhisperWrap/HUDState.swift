import SwiftUI

@MainActor
final class HUDState: ObservableObject {
    enum HUDStatus: Equatable {
        case listening
        case transcribing
        /// Raw text is pasted; the HUD is the small Refine pill.
        case refineOffer
        case processingWithClaude
        case landed
        case failed(String)
    }

    @Published var status: HUDStatus = .listening
    @Published var audioLevel: Float = 0
    /// One-line note under the status (model loading progress etc.). Empty hides it.
    @Published var note = ""
    @Published var recordingStartedAt = Date()

    @Published var availableDevices: [(id: String, name: String)] = []
    @Published var selectedDeviceID: String?

    @Published var prompts: [ClaudePrompt] = []
    @Published var defaultPromptID: UUID?

    var isPill: Bool { status == .refineOffer }
}
