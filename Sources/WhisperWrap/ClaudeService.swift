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
        let custom = customClaudePath.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        let innerStream = shell.streamCommand(executable: effectiveClaudeExecutable, arguments: ["--print", "--model", model], stdinData: inputData)

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

    /// Check if output looks like a Claude CLI error rather than valid content
    static func looksLikeError(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("error:") || lower.contains("traceback") || lower.contains("fatal:")
            || lower.contains("not authenticated") || lower.contains("api error")
    }
}
