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

    /// Process text through Claude CLI, streaming output line by line
    func process(text: String, prompt: String) -> AsyncStream<String> {
        // Escape text for shell: use a temp file to avoid quoting issues
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("claude_input_\(UUID().uuidString).txt")
        let fullPrompt = "\(prompt)\n\n---\n\n\(text)"
        try? fullPrompt.write(to: tempFile, atomically: true, encoding: .utf8)

        let command = "cat \"\(tempFile.path)\" | claude --print 2>&1; rm -f \"\(tempFile.path)\""
        return shell.streamCommand(command)
    }
}
