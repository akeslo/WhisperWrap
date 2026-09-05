import Foundation

@MainActor
class ClaudeService: ObservableObject {
    @Published var isConnected: Bool {
        didSet {
            UserDefaults.standard.set(isConnected, forKey: "claudeConnected")
        }
    }
    @Published var claudePath: String?
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?

    @Published var customClaudePath: String {
        didSet {
            UserDefaults.standard.set(customClaudePath, forKey: "customClaudePath")
        }
    }

    private let shell = ShellService()

    var effectiveClaudeExecutable: String {
        Self.effectiveExecutable(customPath: customClaudePath)
    }

    /// Resolves the executable to invoke: a trimmed custom path override if set, otherwise
    /// the bare `claude` command resolved via PATH. Extracted as a pure static function so
    /// it is testable without instantiating the @MainActor service.
    nonisolated static func effectiveExecutable(customPath: String) -> String {
        let custom = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? "claude" : custom
    }

    init() {
        self.isConnected = UserDefaults.standard.bool(forKey: "claudeConnected")
        self.customClaudePath = UserDefaults.standard.string(forKey: "customClaudePath") ?? ""
    }

    /// Check if claude CLI is installed and return its path
    func checkAvailability() async -> String? {
        if !customClaudePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            claudePath = effectiveClaudeExecutable
            return claudePath
        }

        do {
            let result = try await shell.runCommand(executable: "which", arguments: ["claude"])
            let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                claudePath = path
                return path
            }
        } catch {
            // claude not found in PATH
        }
        claudePath = nil
        return nil
    }

    /// Verify that claude CLI is authenticated by running a trivial command
    func verifyAuth() async -> Bool {
        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        do {
            let result = try await shell.runCommand(executable: effectiveClaudeExecutable, arguments: ["--print", "hello"])
            let output = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // If it returns text without error, auth is good
            if !output.lowercased().contains("error") && !output.lowercased().contains("login") && !output.isEmpty {
                isConnected = true
                return true
            }
            authError = "Claude CLI is not authenticated. Run 'claude' in your terminal to log in."
        } catch {
            authError = "Failed to verify Claude authentication: \(error.localizedDescription)"
        }
        isConnected = false
        return false
    }

    /// Process text through Claude CLI, streaming output line by line.
    /// The returned stream guarantees temp file cleanup on completion or cancellation.
    func process(text: String, prompt: String, model: String = "sonnet") -> AsyncStream<String> {
        let fullPrompt = "\(prompt)\n\n---\n\n\(text)"
        let inputData = fullPrompt.data(using: .utf8)

        // Bounded so a hung `claude` CLI (auth prompt, stalled network) can't wedge the
        // dictation/file-transcription HUD forever — see ShellService.streamCommand (R4).
        let innerStream = shell.streamCommand(executable: effectiveClaudeExecutable, arguments: ["--print", "--model", model], stdinData: inputData, timeout: 60)

        return AsyncStream { continuation in
            let task = Task {
                for await chunk in innerStream {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Outcome of `verifyClaudeSetup()`.
    enum SetupOutcome {
        case success
        case failure(String)
    }

    /// Shared "enable Claude" flow: checks CLI availability, then verifies auth.
    ///
    /// `TranscriptionView.enableClaude()` and `DictationSettingsView.enableClaude()` used to
    /// duplicate this check-then-verify sequence (and its error copy) verbatim (A-SLOP-2) —
    /// each call site now only needs to flip its own "enabled" flag on `.success`.
    func verifyClaudeSetup() async -> SetupOutcome {
        guard await checkAvailability() != nil else {
            return .failure("Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code")
        }
        if await verifyAuth() {
            return .success
        }
        return .failure(authError ?? "Claude CLI is not authenticated. Run 'claude' in your terminal to log in.")
    }

    /// Check if output looks like a Claude CLI error rather than valid content.
    ///
    /// `"error:"` alone is too broad to match anywhere in the output: real transcribed/
    /// processed text can legitimately contain that literal substring mid-sentence (e.g. a
    /// dictated debugging note like "then I got error: file not found"), and that content
    /// would otherwise be discarded as a false-positive CLI error (R5). A genuine CLI error
    /// line always leads with the marker, so `"error:"` is only checked at the start of a
    /// line; the other markers are specific enough to stay substring-anywhere checks.
    nonisolated static func looksLikeError(_ output: String) -> Bool {
        let lower = output.lowercased()
        if lower.contains("traceback") || lower.contains("fatal:")
            || lower.contains("not authenticated") || lower.contains("api error") {
            return true
        }
        return lower
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("error:") }
    }
}
