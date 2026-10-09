import Foundation

struct ClaudePrompt: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var isBuiltin: Bool

    init(id: UUID = UUID(), name: String, prompt: String, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isBuiltin = isBuiltin
    }

    static let builtinPolish = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Polish",
        prompt: "Clean up this dictated text for a casual professional setting. Fix grammar, punctuation, and capitalization. Remove filler words (um, uh, like, you know), false starts, and repeated words. Smooth the phrasing so it reads naturally. Keep the speaker's voice, wording, and meaning; do not add new content. Do not use dashes.",
        isBuiltin: true
    )

    static let builtinSummarize = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Summarize",
        prompt: "Rewrite this as a concise summary: the key points as short lines, each starting with \"• \". Keep names, numbers, and decisions exactly as stated.",
        isBuiltin: true
    )

    static let builtinActionItems = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Action Items",
        prompt: "Rewrite this as a list of action items, one per line, each starting with \"• \" and a verb. Include the owner and due date when stated. If no task is explicit, list the most likely next steps implied by the text.",
        isBuiltin: true
    )

    static let builtinCodeEngineer = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Code Engineer",
        prompt: "Rewrite this as an implementation brief for a coding agent: one line stating the goal, then the concrete requirements and steps, at most six lines total. If no engineering task is explicit, turn the topic into the most plausible concrete task and brief that.",
        isBuiltin: true
    )

    static let builtins: [ClaudePrompt] = [builtinPolish, builtinSummarize, builtinActionItems, builtinCodeEngineer]
}

@MainActor
class ClaudePromptManager: ObservableObject {
    @Published var prompts: [ClaudePrompt] = []

    private let storageKey = "claudeCustomPrompts"
    private let overridesKey = "claudeBuiltinOverrides"

    /// Overrides for builtin prompt text, keyed by UUID string
    @Published var builtinOverrides: [String: String] = [:]

    init() {
        loadPrompts()
        loadOverrides()
    }

    var allPrompts: [ClaudePrompt] {
        Self.applying(overrides: builtinOverrides, to: ClaudePrompt.builtins) + prompts
    }

    /// Applies text overrides (keyed by prompt UUID string) onto a list of builtin prompts,
    /// leaving unmatched builtins untouched. Extracted as a pure static function so the
    /// override-merge logic is testable without instantiating the @MainActor manager.
    nonisolated static func applying(overrides: [String: String], to builtins: [ClaudePrompt]) -> [ClaudePrompt] {
        builtins.map { builtin in
            if let override = overrides[builtin.id.uuidString] {
                return ClaudePrompt(id: builtin.id, name: builtin.name, prompt: override, isBuiltin: true)
            }
            return builtin
        }
    }

    func saveCustomPrompt(name: String, prompt: String) {
        let newPrompt = ClaudePrompt(name: name, prompt: prompt)
        prompts.append(newPrompt)
        persistCustom()
    }

    func updatePrompt(_ prompt: ClaudePrompt, newText: String) {
        if prompt.isBuiltin {
            builtinOverrides[prompt.id.uuidString] = newText
            persistOverrides()
        } else if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index].prompt = newText
            persistCustom()
        }
    }

    func resetBuiltinPrompt(_ prompt: ClaudePrompt) {
        builtinOverrides.removeValue(forKey: prompt.id.uuidString)
        persistOverrides()
    }

    func deleteCustomPrompt(_ prompt: ClaudePrompt) {
        guard !prompt.isBuiltin else { return }
        prompts.removeAll { $0.id == prompt.id }
        persistCustom()
    }

    private func persistCustom() {
        do {
            let data = try JSONEncoder().encode(prompts)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            LoggerService.shared.debug("Failed to persist custom Claude prompts: \(error)")
        }
    }

    private func persistOverrides() {
        UserDefaults.standard.set(builtinOverrides, forKey: overridesKey)
    }

    private func loadPrompts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClaudePrompt].self, from: data) else {
            return
        }
        prompts = decoded
    }

    private func loadOverrides() {
        if let overrides = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] {
            builtinOverrides = overrides
        }
    }
}
