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

    private let shell = ShellService()

    init() {
        self.isConnected = UserDefaults.standard.bool(forKey: "claudeConnected")
    }

    /// Check if claude CLI is installed and return its path
    func checkAvailability() async -> String? {
        do {
            let result = try await shell.runCommand("which claude")
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
            let result = try await shell.runCommand("claude --print \"hello\" 2>&1")
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
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("claude_input_\(UUID().uuidString).txt")
        let fullPrompt = "\(prompt)\n\n---\n\n\(text)"
        try? fullPrompt.write(to: tempFile, atomically: true, encoding: .utf8)

        let command = "cat \"\(tempFile.path)\" | claude --print --model \(model)"
        let innerStream = shell.streamCommand(command)

        return AsyncStream { continuation in
            let task = Task {
                for await chunk in innerStream {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                try? FileManager.default.removeItem(at: tempFile)
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
