import XCTest
@testable import WhisperWrap

/// R7: the json export format was hand-rolled string interpolation that only escaped `"`,
/// producing invalid JSON for text containing a backslash, newline, or other control
/// character, and emitting JSONL under a ".json" extension. WhisperTranscriptionEngine.format
/// is the extracted pure formatting function (no WhisperKit dependency) these exercise.
@MainActor
final class WhisperTranscriptionEngineTests: XCTestCase {
    private func seg(_ start: Float, _ end: Float, _ text: String) -> WhisperTranscriptionEngine.ExportedSegment {
        .init(start: start, end: end, text: text)
    }

    func testTxtFormatJoinsTrimmedSegmentText() throws {
        let segments = [seg(0, 1, "  hello  "), seg(1, 2, "world ")]
        let result = try WhisperTranscriptionEngine.format(segments: segments, as: "txt")
        XCTAssertEqual(result, "hello world")
    }

    func testSrtFormatIncludesIndexAndTimestamps() throws {
        let segments = [seg(0, 1.5, "hi")]
        let result = try WhisperTranscriptionEngine.format(segments: segments, as: "srt")
        XCTAssertTrue(result.contains("1\n00:00:00,000 --> 00:00:01,500\nhi"))
    }

    func testJsonFormatProducesValidJSONForBackslashAndNewline() throws {
        // The original hand-rolled escaping only handled `"` — a backslash or embedded
        // newline produced invalid JSON that would fail to parse.
        let segments = [seg(0, 1, "path\\to\\file and a \"quote\"\nnewline")]
        let result = try WhisperTranscriptionEngine.format(segments: segments, as: "json")
        let data = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try XCTUnwrap(parsed?.first)
        XCTAssertEqual(entry["text"] as? String, "path\\to\\file and a \"quote\"\nnewline")
    }

    func testJsonFormatProducesAnArrayNotJSONL() throws {
        let segments = [seg(0, 1, "a"), seg(1, 2, "b")]
        let result = try WhisperTranscriptionEngine.format(segments: segments, as: "json")
        let data = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(parsed is [[String: Any]], "expected a single JSON array, not JSONL")
    }

    func testJsonFormatRoundTripsStartEndText() throws {
        let segments = [seg(1.25, 3.75, "some text")]
        let result = try WhisperTranscriptionEngine.format(segments: segments, as: "json")
        let data = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try XCTUnwrap(parsed?.first)
        XCTAssertEqual(entry["start"] as? Double ?? -1, 1.25, accuracy: 0.001)
        XCTAssertEqual(entry["end"] as? Double ?? -1, 3.75, accuracy: 0.001)
        XCTAssertEqual(entry["text"] as? String, "some text")
    }
}
