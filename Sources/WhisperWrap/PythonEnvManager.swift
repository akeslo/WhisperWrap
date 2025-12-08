import Foundation

final class PythonEnvManager: @unchecked Sendable {
    private let baseDir: URL
    private let shell: ShellService

    init(applicationSupportDirectory: URL, shell: ShellService) {
        self.baseDir = applicationSupportDirectory
        self.shell = shell
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    var venvPath: URL { baseDir.appendingPathComponent(".venv") }
    var pythonPath: String { venvPath.appendingPathComponent("bin/python").path }
    var pipPath: String { venvPath.appendingPathComponent("bin/pip").path }

    nonisolated func isReady() async -> Bool {
        // Ready if venv exists and faster_whisper imports
        guard FileManager.default.fileExists(atPath: venvPath.path) else { return false }
        let cmd = "\"\(pythonPath)\" - << 'PY'\nimport sys\ntry:\n    import faster_whisper\n    print('OK')\nexcept Exception as e:\n    print(e)\n    sys.exit(1)\nPY"
        do {
            let out = try await shell.runCommand(cmd)
            return out.contains("OK")
        } catch {
            return false
        }
    }

    nonisolated func setup() -> AsyncStream<String> {
        // Create venv and install faster-whisper inside it
        let venv = venvPath.path
        let cmd = """
        /usr/bin/python3 -m venv "\(venv)" && \
        "\(pythonPath)" -m pip install --upgrade pip setuptools wheel && \
        "\(pipPath)" install faster-whisper
        """
        return shell.streamCommand(cmd)
    }
}
