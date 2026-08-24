import XCTest
@testable import WhisperWrap

/// R3: a corrupted persisted hotkey (e.g. `defaults write com.akeslo.WhisperWrap
/// dictationHotkeyKeyCode -int -1`) used to crash the app on every launch via a trapping
/// `UInt32(keyCode)` conversion inside HotKeyManager.registerHotKey. These exercise the
/// out-of-range paths directly against the real Carbon-backed manager: a passing test means
/// no trap occurred (an unguarded trap would abort the whole test process, not just fail
/// an assertion).
final class HotKeyManagerTests: XCTestCase {
    func testRegisterDoesNotTrapOnNegativeKeyCode() {
        let manager = HotKeyManager()
        manager.register(keyCode: -1, modifiers: 0) {}
        // Reaching here means registerHotKey's UInt32(exactly:) guard rejected the value
        // instead of trapping.
    }

    func testRegisterDoesNotTrapOnOutOfRangeKeyCode() {
        let manager = HotKeyManager()
        manager.register(keyCode: Int(UInt32.max) + 1, modifiers: 0) {}
    }

    func testRegisterDoesNotTrapOnNegativeModifiers() {
        let manager = HotKeyManager()
        manager.register(keyCode: 49, modifiers: -1) {}
    }

    func testRegisterAdditionalDoesNotTrapOnNegativeKeyCode() {
        let manager = HotKeyManager()
        manager.registerAdditional(id: 2, keyCode: -1, modifiers: 0) {}
    }
}
