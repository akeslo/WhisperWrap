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
        prompt: "Polish this text for a casual professional setting. Fix grammar, punctuation, and remove filler words. Smooth out rough phrasing while keeping the tone natural and conversational — not stiff or overly formal. Preserve the speaker's voice and original meaning. Return only the polished text. Never ask questions or request clarification — always produce your best output from whatever input is given.",
        isBuiltin: true
    )

    static let builtinSummarize = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Summarize",
        prompt: "Condense this into key points. Be concise. Never ask questions or request clarification — always produce your best output from whatever input is given.",
        isBuiltin: true
    )

    static let builtinActionItems = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Action Items",
        prompt: "Extract action items and to-dos as a bulleted list. Never ask questions or request clarification — always produce your best output from whatever input is given.",
        isBuiltin: true
    )

    static let builtinCodeEngineer = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Code Engineer",
        prompt: "Refactor this into minimal, direct instructions for a senior full-stack engineer who will implement everything provided. Max 3 sentences. Format as a breakdown of tasks and requirements. Never ask questions or request clarification — always produce your best output from whatever input is given.",
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
        let builtins = ClaudePrompt.builtins.map { builtin in
            if let override = builtinOverrides[builtin.id.uuidString] {
                return ClaudePrompt(id: builtin.id, name: builtin.name, prompt: override, isBuiltin: true)
            }
            return builtin
        }
        return builtins + prompts
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
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: storageKey)
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
