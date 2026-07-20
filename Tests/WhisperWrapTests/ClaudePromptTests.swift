import XCTest
@testable import WhisperWrap

/// Covers ClaudePromptManager.applying(overrides:to:) — the builtin-prompt override merge extracted
/// from ClaudePromptManager.allPrompts. Pure, no UserDefaults/@MainActor dependency, so it's
/// testable directly against fixed builtin lists rather than the live ClaudePrompt.builtins.
final class ClaudePromptTests: XCTestCase {
    private let builtinA = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
        name: "Polish", prompt: "original polish prompt", isBuiltin: true
    )
    private let builtinB = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
        name: "Summarize", prompt: "original summarize prompt", isBuiltin: true
    )

    func testReturnsBuiltinsUnchangedWhenThereAreNoOverrides() {
        let result = ClaudePromptManager.applying(overrides: [:], to: [builtinA, builtinB])
        XCTAssertEqual(result, [builtinA, builtinB])
    }

    func testAppliesAnOverrideTextToTheMatchingBuiltinOnly() {
        let overrides = [builtinA.id.uuidString: "custom polish prompt"]
        let result = ClaudePromptManager.applying(overrides: overrides, to: [builtinA, builtinB])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, builtinA.id)
        XCTAssertEqual(result[0].prompt, "custom polish prompt")
        XCTAssertEqual(result[0].name, "Polish") // name is preserved, only prompt text is overridden
        XCTAssertTrue(result[0].isBuiltin)

        XCTAssertEqual(result[1], builtinB) // untouched
    }

    func testAnOverrideKeyedByAnUnknownUUIDHasNoEffect() {
        let overrides = ["11111111-1111-1111-1111-111111111111": "orphaned override"]
        let result = ClaudePromptManager.applying(overrides: overrides, to: [builtinA, builtinB])
        XCTAssertEqual(result, [builtinA, builtinB])
    }

    func testEmptyBuiltinListProducesEmptyResultRegardlessOfOverrides() {
        let result = ClaudePromptManager.applying(
            overrides: [builtinA.id.uuidString: "irrelevant"],
            to: []
        )
        XCTAssertEqual(result, [])
    }
}
