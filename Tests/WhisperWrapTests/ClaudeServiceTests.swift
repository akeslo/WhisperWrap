import XCTest
@testable import WhisperWrap

/// Covers ClaudeService's pure decision logic: which executable to invoke, and whether a
/// captured Claude CLI response reads as an error (vs. real processed content). Both are
/// static functions with no @MainActor/UserDefaults/process dependency, so they're testable
/// directly without spinning up the service or shelling out to a real `claude` binary.
final class ClaudeServiceTests: XCTestCase {

    // MARK: - effectiveExecutable

    func testUsesBareClaudeCommandWhenNoCustomPathIsSet() {
        XCTAssertEqual(ClaudeService.effectiveExecutable(customPath: ""), "claude")
    }

    func testUsesBareClaudeCommandWhenCustomPathIsOnlyWhitespace() {
        XCTAssertEqual(ClaudeService.effectiveExecutable(customPath: "   \n\t"), "claude")
    }

    func testTrimsAndUsesCustomPathWhenSet() {
        XCTAssertEqual(
            ClaudeService.effectiveExecutable(customPath: "  /opt/homebrew/bin/claude  "),
            "/opt/homebrew/bin/claude"
        )
    }

    // MARK: - looksLikeError

    func testDetectsCommonErrorMarkers() {
        XCTAssertTrue(ClaudeService.looksLikeError("Error: something broke"))
        XCTAssertTrue(ClaudeService.looksLikeError("Traceback (most recent call last):"))
        XCTAssertTrue(ClaudeService.looksLikeError("fatal: repository not found"))
        XCTAssertTrue(ClaudeService.looksLikeError("You are not authenticated. Please run 'claude login'."))
        XCTAssertTrue(ClaudeService.looksLikeError("API error: rate limited"))
    }

    func testMarkersAreCaseInsensitive() {
        XCTAssertTrue(ClaudeService.looksLikeError("ERROR: bad request"))
        XCTAssertTrue(ClaudeService.looksLikeError("FATAL: crash"))
    }

    func testDoesNotFlagNormalOutputAsAnError() {
        XCTAssertFalse(ClaudeService.looksLikeError("Here is the polished version of your note."))
        XCTAssertFalse(ClaudeService.looksLikeError(""))
        XCTAssertFalse(ClaudeService.looksLikeError("Action items:\n- follow up with Bob"))
    }

    func testDoesNotFalsePositiveOnSubstringsThatMerelyContainTheWordError() {
        // "error" alone isn't a marker — only "error:" and "api error" are. A word like
        // "errorless" or a sentence mentioning error without a colon must not trip the check.
        XCTAssertFalse(ClaudeService.looksLikeError("This code has zero error handling gaps."))
    }

    func testDoesNotFlagLegitimateContentThatMentionsErrorColonMidSentence() {
        // R5: "error:" is only a genuine CLI-error signal at the start of a line. Real
        // transcribed/processed text can contain the literal substring mid-sentence (e.g. a
        // dictated debugging note), and that must not be discarded as a false-positive error.
        XCTAssertFalse(ClaudeService.looksLikeError("Then I got error: file not found, so I restarted."))
        XCTAssertFalse(ClaudeService.looksLikeError("Action items:\n- mention the error: message to Bob"))
    }

    func testStillFlagsErrorColonAtStartOfALaterLine() {
        XCTAssertTrue(ClaudeService.looksLikeError("Processing...\nerror: something broke"))
    }
}
