import Foundation

/// Carries a non-Sendable value across a concurrency boundary. Used only for
/// `Process`, which is confined to the single detached task that reads it.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Incremental UTF-8 decoder for piped output. A single `read()` can split a
/// multi-byte character across chunk boundaries; decoding each chunk in
/// isolation returns nil for the whole chunk and silently drops up to a full
/// pipe read. This keeps the undecodable tail and prepends it to the next chunk.
private final class UTF8StreamDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var carry = Data()

    /// Decodes as much of `data` as forms complete UTF-8, retaining any partial
    /// trailing character for the next call. Returns nil when nothing is ready.
    func decode(_ data: Data) -> String? {
        lock.lock()
        defer { lock.unlock() }

        carry.append(data)
        // A UTF-8 sequence is at most 4 bytes, so at most 3 trailing bytes can
        // be an incomplete character.
        for backoff in 0...min(3, carry.count) {
            let end = carry.count - backoff
            if let text = String(data: carry.prefix(end), encoding: .utf8) {
                carry.removeFirst(end)
                return text.isEmpty ? nil : text
            }
        }
        return nil
    }

    /// Final flush at EOF. Any bytes still undecodable here are genuinely
    /// invalid rather than merely incomplete, so decode them lossily instead of
    /// discarding them.
    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard !carry.isEmpty else { return nil }
        let text = String(decoding: carry, as: UTF8.self)
        carry.removeAll()
        return text.isEmpty ? nil : text
    }
}

final class ShellService: @unchecked Sendable {
    enum ShellError: Error {
        case commandFailed(String)
    }

    init() {
        _ = ShellService.sigpipeIgnored
    }

    /// Writing to a pipe whose reader has gone away delivers SIGPIPE, whose
    /// default disposition kills the process outright — before any Swift error
    /// handling runs, so `try?` around the write is not enough on its own.
    /// Confirmed empirically: piping oversized stdin to a child that exits
    /// without reading it killed the test binary with signal 13.
    ///
    /// Both shell paths write stdin from a detached task while the child may
    /// already be gone (it can exit early, and `streamCommand` deliberately
    /// terminates it when the consumer cancels), so a broken pipe here is
    /// ordinary. Ignoring the signal turns it into the EPIPE error the throwing
    /// write can report, which the callers discard.
    private static let sigpipeIgnored: Bool = {
        signal(SIGPIPE, SIG_IGN)
        return true
    }()

    private static let enrichedEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let current = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [current]).joined(separator: ":")
        return env
    }()

    nonisolated func runCommand(executable: String, arguments: [String] = [], stdinData: Data? = nil) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        let inPipe = Pipe()

        if stdinData != nil {
            process.standardInput = inPipe
        } else {
            process.standardInput = nil
        }
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = [executable] + arguments
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.environment = ShellService.enrichedEnvironment
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            if let data = stdinData {
                Task.detached {
                    // write(_:) raises an ObjC exception on EPIPE, which is not
                    // catchable in Swift and takes the app down. The child can be
                    // gone before we finish writing -- it may exit early, or a
                    // cancelled stream may have terminated it -- so a broken pipe
                    // here is ordinary, not exceptional. The throwing variant
                    // turns it into an error we can discard.
                    try? inPipe.fileHandleForWriting.write(contentsOf: data)
                    try? inPipe.fileHandleForWriting.close()
                }
            }

            // Drain the pipe concurrently with the child process. Reading only
            // once the process has terminated deadlocks any child that writes
            // more than the pipe buffer (~64KB): it blocks on write, never
            // exits, and the await here would hang forever.
            let box = UncheckedSendableBox(process)
            Task.detached {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let process = box.value
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ShellError.commandFailed(output))
                }
            }
        }
    }
    
    nonisolated func streamCommand(executable: String, arguments: [String] = [], stdinData: Data? = nil) -> AsyncStream<String> {
        AsyncStream { continuation in
            let process = Process()
            let pipe = Pipe()
            let inPipe = Pipe()

            if stdinData != nil {
                process.standardInput = inPipe
            } else {
                process.standardInput = nil
            }
            
            process.standardOutput = pipe
            process.standardError = pipe
            process.arguments = [executable] + arguments
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.environment = ShellService.enrichedEnvironment

            let decoder = UTF8StreamDecoder()

            pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    // EOF — stop handler, don't yield empty strings
                    fileHandle.readabilityHandler = nil
                    return
                }
                if let text = decoder.decode(data) {
                    continuation.yield(text)
                }
            }

            process.terminationHandler = { _ in
                // Stop handler first, then drain any remaining data
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty, let text = decoder.decode(remaining) {
                    continuation.yield(text)
                }
                if let tail = decoder.flush() {
                    continuation.yield(tail)
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
                if let data = stdinData {
                    Task.detached {
                        // Same broken-pipe hazard as runCommand, and more likely
                        // here: onTermination terminates the child when the
                        // consumer cancels, which routinely happens mid-write for
                        // a long transcript.
                        try? inPipe.fileHandleForWriting.write(contentsOf: data)
                        try? inPipe.fileHandleForWriting.close()
                    }
                }
            } catch {
                continuation.finish()
            }
        }
    }
}
