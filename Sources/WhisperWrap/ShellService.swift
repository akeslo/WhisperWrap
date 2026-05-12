import Foundation

final class ShellService: @unchecked Sendable {
    enum ShellError: Error {
        case commandFailed(String)
    }

    init() {}

    private static let enrichedEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [current]).joined(separator: ":")
        return env
    }()

    nonisolated func runCommand(_ command: String) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.standardInput = nil
        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = ["-c", command]
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.environment = ShellService.enrichedEnvironment
        
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ShellError.commandFailed(output))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    nonisolated func streamCommand(_ command: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            let process = Process()
            let pipe = Pipe()

            process.standardInput = nil
            process.standardOutput = pipe
            process.standardError = pipe
            process.arguments = ["-c", command]
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.environment = ShellService.enrichedEnvironment

            pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    // EOF — stop handler, don't yield empty strings
                    fileHandle.readabilityHandler = nil
                    return
                }
                if let text = String(data: data, encoding: .utf8) {
                    continuation.yield(text)
                }
            }

            process.terminationHandler = { _ in
                // Stop handler first, then drain any remaining data
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                    continuation.yield(text)
                }
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish()
            }
        }
    }
}
