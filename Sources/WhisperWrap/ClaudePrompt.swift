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
        prompt: "Act as an expert copy editor. Polish the provided text for a casual professional setting. Correct grammar and punctuation while removing filler words. Smooth the phrasing to sound natural and conversational, avoiding rigid formality.  Do not use \"-\". Preserve the original voice and meaning entirely. Output only the revised text. Make your best assumptions and provide the final result without asking questions.",
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
        prompt: "Process this input as a senior full-stack engineer and generate a concise implementation breakdown (maximum 3 sentences). Output only the direct tasks and requirements needed to build it. Make your best assumptions and provide a complete, actionable solution without requesting clarification.",
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
