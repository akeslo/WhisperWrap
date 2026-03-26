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

    static let builtinCleanUp = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Clean Up",
        prompt: "Fix grammar, punctuation, and remove filler words. Keep the original meaning intact. Return only the cleaned text.",
        isBuiltin: true
    )

    static let builtinSummarize = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Summarize",
        prompt: "Condense this into key points. Be concise.",
        isBuiltin: true
    )

    static let builtinActionItems = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Action Items",
        prompt: "Extract action items and to-dos as a bulleted list.",
        isBuiltin: true
    )

    static let builtins: [ClaudePrompt] = [builtinCleanUp, builtinSummarize, builtinActionItems]
}

@MainActor
class ClaudePromptManager: ObservableObject {
    @Published var prompts: [ClaudePrompt] = []

    private let storageKey = "claudeCustomPrompts"

    init() {
        loadPrompts()
    }

    var allPrompts: [ClaudePrompt] {
        ClaudePrompt.builtins + prompts
    }

    func saveCustomPrompt(name: String, prompt: String) {
        let newPrompt = ClaudePrompt(name: name, prompt: prompt)
        prompts.append(newPrompt)
        persist()
    }

    func deleteCustomPrompt(_ prompt: ClaudePrompt) {
        guard !prompt.isBuiltin else { return }
        prompts.removeAll { $0.id == prompt.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadPrompts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClaudePrompt].self, from: data) else {
            return
        }
        prompts = decoded
    }
}
