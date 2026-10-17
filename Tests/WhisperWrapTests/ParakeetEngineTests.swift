import XCTest
@testable import WhisperWrap

/// R7: the json export format was hand-rolled string interpolation that only escaped `"`,
/// producing invalid JSON for text containing a backslash, newline, or other control
/// character, and emitting JSONL under a ".json" extension. ParakeetEngine.format
/// is the extracted pure formatting function (no model needed) these exercise.
@MainActor
final class ParakeetEngineTests: XCTestCase {
    private func seg(_ start: Float, _ end: Float, _ text: String) -> ParakeetEngine.ExportedSegment {
        .init(start: start, end: end, text: text)
    }

    func testTxtFormatJoinsTrimmedSegmentText() throws {
        let segments = [seg(0, 1, "  hello  "), seg(1, 2, "world ")]
        let result = try ParakeetEngine.format(segments: segments, as: "txt")
        XCTAssertEqual(result, "hello world")
    }

    func testSrtFormatIncludesIndexAndTimestamps() throws {
        let segments = [seg(0, 1.5, "hi")]
        let result = try ParakeetEngine.format(segments: segments, as: "srt")
        XCTAssertTrue(result.contains("1\n00:00:00,000 --> 00:00:01,500\nhi"))
    }

    func testJsonFormatProducesValidJSONForBackslashAndNewline() throws {
        // The original hand-rolled escaping only handled `"` — a backslash or embedded
        // newline produced invalid JSON that would fail to parse.
        let segments = [seg(0, 1, "path\\to\\file and a \"quote\"\nnewline")]
        let result = try ParakeetEngine.format(segments: segments, as: "json")
        let data = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try XCTUnwrap(parsed?.first)
        XCTAssertEqual(entry["text"] as? String, "path\\to\\file and a \"quote\"\nnewline")
    }

    func testJsonFormatProducesAnArrayNotJSONL() throws {
        let segments = [seg(0, 1, "a"), seg(1, 2, "b")]
        let result = try ParakeetEngine.format(segments: segments, as: "json")
        let data = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(parsed is [[String: Any]], "expected a single JSON array, not JSONL")
    }

    func testJsonFormatRoundTripsStartEndText() throws {
        let segments = [seg(1.25, 3.75, "some text")]
        let result = try ParakeetEngine.format(segments: segments, as: "json")
        let data = try XCTUnwrap(result.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try XCTUnwrap(parsed?.first)
        XCTAssertEqual(entry["start"] as? Double ?? -1, 1.25, accuracy: 0.001)
        XCTAssertEqual(entry["end"] as? Double ?? -1, 3.75, accuracy: 0.001)
        XCTAssertEqual(entry["text"] as? String, "some text")
    }

    func testSegmentsSplitAtSentenceEndAndPause() {
        let toks: [(text: String, start: Float, end: Float)] = [
            ("▁Hello", 0.0, 0.4), ("▁world", 0.4, 0.8), (".", 0.8, 0.9),
            ("▁Next", 1.0, 1.3), ("▁bit", 1.3, 1.5), ("▁after", 3.0, 3.4), ("▁pause", 3.4, 3.8),
        ]
        let segs = ParakeetEngine.segments(tokens: toks, fallbackText: "", duration: 4)
        XCTAssertEqual(segs, [
            .init(start: 0.0, end: 0.9, text: "Hello world."),
            .init(start: 1.0, end: 1.5, text: "Next bit"),
            .init(start: 3.0, end: 3.8, text: "after pause"),
        ])
    }

    func testSegmentsWithoutTimingsSpanDuration() {
        XCTAssertEqual(ParakeetEngine.segments(tokens: [], fallbackText: " hi ", duration: 2.5),
                       [.init(start: 0, end: 2.5, text: "hi")])
        XCTAssertEqual(ParakeetEngine.segments(tokens: [], fallbackText: "", duration: 2.5), [])
    }
}
