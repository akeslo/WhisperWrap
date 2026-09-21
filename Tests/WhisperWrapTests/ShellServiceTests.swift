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

    // MARK: - UTF8StreamDecoder split-multibyte carry (via streamCommand)
    //
    // UTF8StreamDecoder is `private` to ShellService.swift, so it can't be driven
    // directly even with @testable import. These tests exercise it through
    // streamCommand's readabilityHandler instead: a child process that writes a
    // multibyte UTF-8 character's bytes across two (or three) separate writes,
    // with a sleep between them, forces the pipe to deliver them as separate
    // `availableData` reads — reproducing exactly the split-read scenario the
    // decoder's carry buffer exists to handle. Without it, each partial read
    // would fail `String(data:encoding:.utf8)` and either drop or mangle the
    // character.

    /// € (U+20AC) is 3 bytes (0xE2 0x82 0xAC). Split 1 byte / 2 bytes.
    func testStreamCommandReassemblesA3ByteCharacterSplitAcrossTwoReads() async {
        let shell = ShellService()
        let stream = shell.streamCommand(
            executable: "sh",
            arguments: ["-c", "printf '\\xe2'; sleep 0.2; printf '\\x82\\xac'"]
        )

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.joined(), "\u{20AC}")
    }

    /// 🎉 (U+1F389) is 4 bytes (0xF0 0x9F 0x8E 0x89). Split 1 / 1 / 2 across
    /// three reads, exercising the decoder's up-to-3-trailing-byte backoff.
    func testStreamCommandReassemblesA4ByteCharacterSplitAcrossThreeReads() async {
        let shell = ShellService()
        let stream = shell.streamCommand(
            executable: "sh",
            arguments: [
                "-c",
                "printf '\\xf0'; sleep 0.2; printf '\\x9f'; sleep 0.2; printf '\\x8e\\x89'"
            ]
        )

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.joined(), "\u{1F389}")
    }

    /// A multibyte character surrounded by plain ASCII, still split mid-character,
    /// must not lose or corrupt the surrounding text.
    func testStreamCommandReassemblesASplitCharacterAmidPlainText() async {
        let shell = ShellService()
        let stream = shell.streamCommand(
            executable: "sh",
            arguments: ["-c", "printf 'cost: \\xe2'; sleep 0.2; printf '\\x82\\xac done'"]
        )

        var chunks: [String] = []
        for await chunk in stream {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks.joined(), "cost: \u{20AC} done")
    }
}
