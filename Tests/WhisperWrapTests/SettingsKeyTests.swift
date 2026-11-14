import XCTest
@testable import WhisperWrap

/// The keys are persisted, so each must stay byte-identical to the literal it replaced.
final class SettingsKeyTests: XCTestCase {
    func testKeysMatchTheirPersistedLiterals() {
        XCTAssertEqual(SettingsKey.autoCopy, "autoCopy")
        XCTAssertEqual(SettingsKey.autoRefine, "autoRefine")
        XCTAssertEqual(SettingsKey.showHUD, "showHUD")
        XCTAssertEqual(SettingsKey.saveRecordings, "saveRecordings")
        XCTAssertEqual(SettingsKey.recordingsSaveDirectory, "recordingsSaveDirectory")
        XCTAssertEqual(SettingsKey.dictationClaudePromptID, "dictationClaudePromptID")
        XCTAssertEqual(SettingsKey.dictationClaudeModel, "dictationClaudeModel")
        XCTAssertEqual(SettingsKey.selectedAudioDeviceID, "selectedAudioDeviceID")
    }
}
