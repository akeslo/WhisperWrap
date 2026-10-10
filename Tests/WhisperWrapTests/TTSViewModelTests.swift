import XCTest
@testable import WhisperWrap

/// Offline coverage for TTSViewModel's pure state logic: the credits label, the speak()
/// re-entry guards (A-SLOP-8), and the system-voice filtering. Never touches the network,
/// the audio engine, or the stored API key (apiKey's didSet writes the Keychain).
@MainActor
final class TTSViewModelTests: XCTestCase {

    // MARK: - creditsDisplayString

    func testCreditsDisplayDefaultsToPlaceholder() {
        let vm = TTSViewModel()
        vm.characterLimit = 0
        vm.creditsError = nil
        vm.isFetchingCredits = false
        XCTAssertEqual(vm.creditsDisplayString, "Usage: -- / --")
    }

    func testCreditsDisplayShowsUsageWhenLimitKnown() {
        let vm = TTSViewModel()
        vm.usedCharacterCount = 1200
        vm.characterLimit = 10_000
        vm.creditsError = nil
        vm.isFetchingCredits = false
        XCTAssertEqual(vm.creditsDisplayString, "Usage: 1200 / 10000")
    }

    func testCreditsDisplayLoadingWinsOverErrorAndUsage() {
        let vm = TTSViewModel()
        vm.characterLimit = 10_000
        vm.creditsError = "Credits: N/A (No Permission)"
        vm.isFetchingCredits = true
        XCTAssertEqual(vm.creditsDisplayString, "Usage: Loading...")
    }

    func testCreditsDisplayErrorWinsOverUsage() {
        let vm = TTSViewModel()
        vm.characterLimit = 10_000
        vm.isFetchingCredits = false
        vm.creditsError = "Credits: N/A (No Permission)"
        XCTAssertEqual(vm.creditsDisplayString, "Credits: N/A (No Permission)")
    }

    // MARK: - speak() guards

    func testSpeakWithEmptyTextLeavesStateAlone() {
        let vm = TTSViewModel()
        vm.text = ""
        vm.errorMessage = "stale"
        vm.speak()
        XCTAssertEqual(vm.errorMessage, "stale", "empty text returns before clearing the error")
        XCTAssertFalse(vm.isDownloadingAudio)
        XCTAssertFalse(vm.isSpeaking)
    }

    func testSpeakWhileRenderInFlightDoesNotStartASecondRender() {
        let vm = TTSViewModel()
        vm.selectedEngine = .system
        vm.text = "hello"
        vm.isDownloadingAudio = true
        vm.errorMessage = "stale"
        vm.speak()
        XCTAssertNil(vm.errorMessage, "speak() clears the error before the guards")
        XCTAssertTrue(vm.isDownloadingAudio)
        XCTAssertFalse(vm.isSpeaking)
        XCTAssertNil(vm.lastAudioData, "no second render may populate the cache")
    }

    func testSpeakWhileAlreadySpeakingIsANoOp() {
        let vm = TTSViewModel()
        vm.selectedEngine = .system
        vm.text = "hello"
        vm.isSpeaking = true
        vm.speak()
        XCTAssertFalse(vm.isDownloadingAudio)
        XCTAssertTrue(vm.isSpeaking)
    }

    // MARK: - System voices

    func testSystemVoicesAreEnglishNonNoveltyAndSortedByName() {
        let vm = TTSViewModel()
        let novelty: Set<String> = ["Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos",
                                    "Deranged", "Good News", "Hysterical", "Junior", "Kathy", "Organ",
                                    "Pipe Organ", "Princess", "Ralph", "Trinoids", "Whisper", "Zarvox"]
        let names = vm.availableSystemVoices.map(\.name)
        XCTAssertEqual(names, names.sorted())
        XCTAssertEqual(names.count, Set(names).count, "voices are de-duplicated by name")
        for voice in vm.availableSystemVoices {
            XCTAssertTrue(voice.language.starts(with: "en"), "\(voice.name) is not English")
            XCTAssertFalse(novelty.contains(voice.name), "\(voice.name) is a novelty voice")
        }
        if let selected = vm.selectedSystemVoice {
            XCTAssertTrue(vm.availableSystemVoices.contains(selected))
        } else {
            XCTAssertTrue(vm.availableSystemVoices.isEmpty)
        }
    }
}
