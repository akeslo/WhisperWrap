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
}
