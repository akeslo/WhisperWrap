import XCTest
@testable import WhisperWrap

/// FileHandle's `write(_:)` raises an ObjC exception on EPIPE, which Swift cannot
/// catch — it terminates the app. Both shell paths write stdin from a detached
/// task while the child may already be gone: a command can exit without reading
/// its input, and `streamCommand`'s onTermination deliberately terminates the
/// child when the consumer cancels. Those are ordinary situations here, so the
/// write must fail quietly rather than take WhisperWrap down mid-dictation.
final class ShellServiceTests: XCTestCase {
    /// Larger than a pipe buffer (64KB), so the write cannot complete before the
    /// child exits and must hit the broken pipe.
    private var oversizedInput: Data {
        Data(repeating: UInt8(ascii: "x"), count: 512 * 1024)
    }

    func testRunCommandSurvivesAChildThatNeverReadsStdin() async throws {
        let shell = ShellService()
        // `true` exits immediately without draining stdin.
        let output = try await shell.runCommand(executable: "true", stdinData: oversizedInput)
        XCTAssertEqual(output, "")
    }

    func testStreamCommandSurvivesAChildThatNeverReadsStdin() async {
        let shell = ShellService()
        let stream = shell.streamCommand(executable: "true", stdinData: oversizedInput)

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        XCTAssertTrue(chunks.joined().isEmpty)
    }

    func testStreamCommandStillDeliversOutput() async {
        let shell = ShellService()
        let stream = shell.streamCommand(executable: "echo", arguments: ["hello"])

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.joined().trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    /// R4: a child that never terminates (e.g. `claude` stuck on an auth prompt) used to
    /// wedge the consumer forever — nothing but explicit stream cancellation ever called
    /// `process.terminate()`. A `timeout` now force-terminates it and surfaces an
    /// `"error:"`-tagged chunk so `ClaudeService.looksLikeError` catches it.
    func testStreamCommandTimesOutAHungChild() async {
        let shell = ShellService()
        // `sleep 30` never writes to stdout, simulating a hung child.
        let stream = shell.streamCommand(executable: "sleep", arguments: ["30"], timeout: 0.2)

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        let joined = chunks.joined()
        XCTAssertTrue(joined.lowercased().contains("error:"), "expected a timeout error chunk, got: \(joined)")
    }

    func testStreamCommandWithoutTimeoutDoesNotSpuriouslyTimeOut() async {
        let shell = ShellService()
        let stream = shell.streamCommand(executable: "echo", arguments: ["hello"], timeout: 5)

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        let joined = chunks.joined()
        XCTAssertFalse(joined.lowercased().contains("error:"))
        XCTAssertEqual(joined.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }
}
