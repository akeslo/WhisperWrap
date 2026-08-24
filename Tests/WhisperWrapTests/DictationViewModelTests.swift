import XCTest
@testable import WhisperWrap

/// Comprehensive test coverage for DictationViewModel.transcribe() — the core post-transcription
/// logic that handles Claude processing, HUD state management, clipboard operations, and error
/// detection. Covers 7 decision points across 10 test cases.
@MainActor
final class DictationViewModelTests: XCTestCase {

    // MARK: - Test 1: Claude Disabled Path

    func testTranscribeWithClaudeDisabled_ReturnsRawTranscriptionOnly() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hello world"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = false
        mockContentViewModel.transcriptionResult = rawText

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertEqual(viewModel.lastRawTranscription, rawText)
        XCTAssertEqual(viewModel.transcribedText, rawText)
        XCTAssertEqual(viewModel.lastProcessedOutput, "")
        XCTAssertFalse(mockClaudeService.wasProcessCalled)
    }

    // MARK: - Test 2: Claude Enabled + Success

    func testTranscribeWithClaudeEnabled_ReturnsClaudeOutput() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hello world"
        let claudeOutput = "Hello, World!"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = rawText
        mockClaudeService.processResult = claudeOutput

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertEqual(viewModel.lastRawTranscription, rawText)
        XCTAssertEqual(viewModel.transcribedText, claudeOutput)
        XCTAssertEqual(viewModel.lastProcessedOutput, claudeOutput)
        XCTAssertTrue(mockClaudeService.wasProcessCalled)
    }

    // MARK: - Test 3: Claude Enabled + Error Detected

    func testTranscribeDetectsClaudeError_RevertsToRawAndMarksDisconnected() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hello world"
        let errorOutput = "Error: API rate limited"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = rawText
        mockClaudeService.processResult = errorOutput
        mockClaudeService.isConnected = true

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertEqual(viewModel.transcribedText, rawText)
        XCTAssertEqual(viewModel.lastRawTranscription, rawText)
        XCTAssertEqual(viewModel.lastProcessedOutput, "")
        XCTAssertFalse(mockClaudeService.isConnected)
    }

    // MARK: - Test 4: AutoCopy True

    func testAutoCopyTrue_CopiesTranscriptionToClipboard() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hello world"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.autoCopy = true
        viewModel.claudeEnabled = false
        mockContentViewModel.transcriptionResult = rawText
        NSPasteboard.general.clearContents()

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertEqual(clipboard, rawText)
    }

    // MARK: - Test 5: AutoCopy False

    func testAutoCopyFalse_DoesNotCopyToClipboard() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hello world"
        let originalClipboard = "original content"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.autoCopy = false
        viewModel.claudeEnabled = false
        mockContentViewModel.transcriptionResult = rawText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(originalClipboard, forType: .string)

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertEqual(clipboard, originalClipboard)
    }

    // MARK: - U4: "No Speech Detected" sentinel is never auto-copied

    func testAutoCopyTrue_DoesNotCopyNoSpeechDetectedSentinel() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let originalClipboard = "something the user actually copied"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.autoCopy = true
        viewModel.claudeEnabled = false
        // transcribeDictation returns this literal sentinel for a take with no speech
        // (ContentViewModel.transcribeDictation / noSpeechDetectedSentinel).
        mockContentViewModel.transcriptionResult = ContentViewModel.noSpeechDetectedSentinel
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(originalClipboard, forType: .string)

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertEqual(clipboard, originalClipboard, "the no-speech sentinel must never overwrite the user's clipboard")
    }

    // MARK: - Test 6: Empty/Whitespace Transcription

    func testEmptyTranscription_HandlesGracefully() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = "   \n\t  "

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertFalse(mockClaudeService.wasProcessCalled)
    }

    // MARK: - Test 7: Empty String Transcription

    func testEmptyStringTranscription_SkipsClaude() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = ""

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertFalse(mockClaudeService.wasProcessCalled)
    }

    // MARK: - Test 8: Claude Output Preserves Valid Text

    func testClaudeOutput_PreservesValidText() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hello world this is a test"
        let claudeOutput = "Hello world, this is a test."
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = rawText
        mockClaudeService.processResult = claudeOutput

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertEqual(viewModel.transcribedText, claudeOutput)
        XCTAssertNotEqual(viewModel.transcribedText, rawText)
    }

    // MARK: - Test 9: Error Detection with Traceback

    func testErrorDetection_RecognizesTraceback() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "test"
        let errorOutput = "Traceback (most recent call last):\n  File \"test.py\", line 1"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = rawText
        mockClaudeService.processResult = errorOutput
        mockClaudeService.isConnected = true

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertEqual(viewModel.transcribedText, rawText)
        XCTAssertFalse(mockClaudeService.isConnected)
    }

    // MARK: - Test 10: Different Raw and Processed Output

    func testDifferentRawAndProcessed_StoresCorrectly() async throws {
        let viewModel = DictationViewModel()
        let mockClaudeService = MockClaudeService()
        let mockClaudePromptManager = MockClaudePromptManager()
        let mockContentViewModel = MockContentViewModel()

        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager
        viewModel.contentViewModel = mockContentViewModel

        let rawText = "hi"
        let processedText = "Hello"
        let audioURL = URL(fileURLWithPath: "/tmp/test.wav")

        viewModel.claudeEnabled = true
        viewModel.showHUD = false
        mockContentViewModel.transcriptionResult = rawText
        mockClaudeService.processResult = processedText

        viewModel.transcribe(url: audioURL)
        await waitForProcessing(viewModel)

        XCTAssertEqual(viewModel.lastRawTranscription, rawText)
        XCTAssertEqual(viewModel.transcribedText, processedText)
        XCTAssertEqual(viewModel.lastProcessedOutput, processedText)
    }

    // MARK: - Helpers

    private func waitForProcessing(_ viewModel: DictationViewModel) async {
        var attempts = 0
        while viewModel.isProcessing && attempts < 100 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            attempts += 1
        }
    }
}

// MARK: - Mock Services

@MainActor
class MockClaudeService: ClaudeService {
    var wasProcessCalled = false
    var processResult: String = ""

    override func process(text: String, prompt: String, model: String = "sonnet") -> AsyncStream<String> {
        wasProcessCalled = true
        let result = processResult

        return AsyncStream { continuation in
            Task {
                continuation.yield(result)
                continuation.finish()
            }
        }
    }
}

@MainActor
class MockContentViewModel: ContentViewModel {
    var transcriptionResult: String = ""

    override func transcribeDictation(audioURL: URL, model: Model) async throws -> String {
        return transcriptionResult
    }
}

@MainActor
class MockClaudePromptManager: ClaudePromptManager {
    override var allPrompts: [ClaudePrompt] {
        [ClaudePrompt.builtinPolish, ClaudePrompt.builtinSummarize]
    }
}
