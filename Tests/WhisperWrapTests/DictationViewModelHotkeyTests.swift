import XCTest
import Carbon
@testable import WhisperWrap

/// Covers DictationViewModel.character(forKeyCode:) — the Carbon-key-code → display-character
/// mapping used by the hotkey settings UI. Extracted as a pure static function specifically so
/// it is testable without spinning up the full view model (audio session, hotkey manager,
/// launch-at-login state, etc.), following the same pure-helper extraction pattern used by
/// macHermit's FallbackService usage-parsing helpers.
final class DictationViewModelHotkeyTests: XCTestCase {
    func testMapsLetterKeysToUppercaseCharacters() {
        XCTAssertEqual(DictationViewModel.character(forKeyCode: kVK_ANSI_A), "A")
        XCTAssertEqual(DictationViewModel.character(forKeyCode: kVK_ANSI_Z), "Z")
    }

    func testMapsDigitKeysToDigitStrings() {
        XCTAssertEqual(DictationViewModel.character(forKeyCode: kVK_ANSI_0), "0")
        XCTAssertEqual(DictationViewModel.character(forKeyCode: kVK_ANSI_9), "9")
    }

    func testMapsSpaceToItsName() {
        XCTAssertEqual(DictationViewModel.character(forKeyCode: kVK_Space), "Space")
    }

    func testReturnsNilForAnUnmappedKeyCode() {
        // kVK_Escape (53) is a real Carbon key code but is not in the hotkey map.
        XCTAssertNil(DictationViewModel.character(forKeyCode: kVK_Escape))
    }

    func testReturnsNilForAnOutOfRangeKeyCode() {
        XCTAssertNil(DictationViewModel.character(forKeyCode: -1))
        XCTAssertNil(DictationViewModel.character(forKeyCode: 9999))
    }
}
