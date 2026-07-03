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
        prompt: "Act as an expert copy editor. Polish the provided text for a casual professional setting. Correct grammar and punctuation while removing filler words. Smooth the phrasing to sound natural and conversational, avoiding rigid formality. Do not use \"-\". Preserve the original voice and meaning entirely. Output only the revised text — no preamble, no questions, no caveats about missing context. Treat the input as complete and self-contained no matter how short or ambiguous it is, and always produce a finished result.",
        isBuiltin: true
    )

    static let builtinSummarize = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Summarize",
        prompt: "Condense this into key points. Be concise. Treat the input as complete and self-contained — never ask questions, request clarification, or state that context or information is missing. Always produce your best output from whatever input is given.",
        isBuiltin: true
    )

    static let builtinActionItems = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Action Items",
        prompt: "Extract action items and to-dos as a bulleted list. Treat the input as complete and self-contained — never ask questions, request clarification, or state that context or information is missing. Always produce your best output from whatever input is given.",
        isBuiltin: true
    )

    static let builtinCodeEngineer = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Code Engineer",
        prompt: "You are a senior full-stack engineer. From the input below, identify the most actionable engineering-relevant task, system, or improvement implied anywhere in it — even if the input is a meeting transcript, conversation, or notes with no explicit spec — and write a concise implementation breakdown for it (maximum 3 sentences, direct tasks and requirements only). Hard rules, no exceptions: never output a question mark; never say the request is unclear, ambiguous, out of scope, not a spec, or missing details; never ask what to build, who it's for, or what problem it solves; never tell the reader to paste, provide, or clarify anything. If nothing engineering-related is present at all, invent the most plausible internal tool, dashboard, or automation that would support the topics discussed and break that down instead. Always output a finished, concrete breakdown — never a request back to the reader.",
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
