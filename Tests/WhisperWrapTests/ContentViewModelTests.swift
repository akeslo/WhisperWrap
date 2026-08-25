import XCTest
@testable import WhisperWrap

/// Covers ContentViewModel.processAudio() — the file-transcription entry point with:
/// - Security-scoped resource access (sandbox sandbox permission handling)
/// - Optional Claude AI post-processing
/// - File I/O (write, replacement, cleanup)
/// - Cancellation at multiple stages
/// - Error detection and fallback paths
///
/// Uses temporary directories (XCTestCase.temporaryDirectory) for real file I/O, mock
/// services for transcription/Claude processing, and task cancellation to test mid-flight
/// interruption paths.
@MainActor
final class ContentViewModelTests: XCTestCase {

    var viewModel: ContentViewModel!
    var mockClaudeService: ContentMockClaudeService!
    var mockClaudePromptManager: ContentMockClaudePromptManager!
    var mockTranscriptionEngine: ContentMockWhisperTranscriptionEngine!
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        // ContentViewModel.init() reads a saved prompt ID from UserDefaults.standard, which
        // persists across test runs (and across separate `swift test` invocations) since it's
        // real UserDefaults, not a test double. Clear it so each test starts from the
        // documented default (ClaudePrompt.builtinPolish.id) instead of whatever a previous
        // test happened to leave behind.
        UserDefaults.standard.removeObject(forKey: "fileClaudePromptID")
        mockTranscriptionEngine = ContentMockWhisperTranscriptionEngine()
        viewModel = ContentViewModel(transcriptionEngine: mockTranscriptionEngine)
        mockClaudeService = ContentMockClaudeService()
        mockClaudePromptManager = ContentMockClaudePromptManager()
        viewModel.claudeService = mockClaudeService
        viewModel.claudePromptManager = mockClaudePromptManager

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Basic transcription without Claude

    func testTranscribesAudioFileAndWritesOutputWhenClaudeDisabled() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "test-audio.mp3")
        let expectedTranscription = "This is a test transcription of the audio."

        mockTranscriptionEngine.nextTranscription = expectedTranscription

        viewModel.fileClaudeEnabled = false

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: false
        )

        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(viewModel.consoleOutput.contains("✅ Transcription saved"))

        // Verify output file was created with raw transcription
        let outputFile = audioURL.deletingPathExtension().appendingPathExtension("txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))

        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertEqual(content, expectedTranscription)
    }

    func testWritesRawTranscriptionToOutputFileWhenClaudeServiceNotConfigured() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "audio-no-claude.m4a")
        let expectedTranscription = "Raw transcription without processing."

        mockTranscriptionEngine.nextTranscription = expectedTranscription

        viewModel.claudeService = nil  // No Claude service
        viewModel.fileClaudeEnabled = true

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: true
        )

        // Then
        let outputFile = audioURL.deletingPathExtension().appendingPathExtension("txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertEqual(content, expectedTranscription)
    }

    // MARK: - Empty transcription

    func testSkipsCloudeProcessingAndLogsWarningWhenTranscriptionIsEmpty() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "silent-audio.mp3")
        let emptyTranscription = "   \n\t  "

        mockTranscriptionEngine.nextTranscription = emptyTranscription

        viewModel.fileClaudeEnabled = true
        mockClaudeService.nextProcessResult = "This should not be used"

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: true
        )

        // Then
        XCTAssertTrue(
            viewModel.consoleOutput.contains("⚠️ Transcription was empty"),
            "Should log empty transcription warning"
        )
        XCTAssertFalse(
            mockClaudeService.wasProcessCalled,
            "Should not call Claude when transcription is empty"
        )
    }

    // MARK: - Claude processing enabled and success

    func testProcessesTranscriptionWithClaudeAndReplacesOutputFileOnSuccess() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "process-with-claude.mp3")
        let rawTranscription = "Here is the original messy transcription with no punctuation"
        let claudeProcessed = "Here is the original, messy transcription with no punctuation."

        mockTranscriptionEngine.nextTranscription = rawTranscription

        viewModel.fileClaudeEnabled = true
        mockClaudeService.nextProcessResult = claudeProcessed

        let testPrompt = ClaudePrompt(
            id: UUID(),
            name: "Test Prompt",
            prompt: "Fix punctuation"
        )
        mockClaudePromptManager.setTestPrompts([testPrompt])
        viewModel.fileClaudePromptID = testPrompt.id

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: true
        )

        // Then
        XCTAssertTrue(
            viewModel.consoleOutput.contains("✅ Claude processing complete"),
            "Should log successful Claude processing"
        )
        XCTAssertTrue(mockClaudeService.wasProcessCalled)

        let outputFile = audioURL.deletingPathExtension().appendingPathExtension("txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertEqual(
            content,
            claudeProcessed,
            "Output file should contain Claude-processed text, not raw"
        )
    }

    func testUsesSelectedClaudePromptWhenProcessing() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "prompt-test.mp3")
        mockTranscriptionEngine.nextTranscription = "Test transcription"

        viewModel.fileClaudeEnabled = true

        let prompt1 = ClaudePrompt(id: UUID(), name: "Prompt 1", prompt: "Polish")
        let prompt2 = ClaudePrompt(id: UUID(), name: "Prompt 2", prompt: "Summarize")
        mockClaudePromptManager.setTestPrompts([prompt1, prompt2])
        viewModel.fileClaudePromptID = prompt2.id

        mockClaudeService.nextProcessResult = "Processed output"

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: true
        )

        // Then
        XCTAssertTrue(mockClaudeService.wasProcessCalled)
        XCTAssertEqual(
            mockClaudeService.lastProcessedPrompt,
            "Summarize",
            "Should use the selected prompt (Prompt 2)"
        )
    }

    // MARK: - Claude error detection and fallback

    func testDetectsClaudeErrorAndFallsBackToRawTranscription() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "claude-error.mp3")
        let rawTranscription = "Original transcription text"
        let claudeError = "Error: API rate limit exceeded"

        mockTranscriptionEngine.nextTranscription = rawTranscription

        viewModel.fileClaudeEnabled = true
        mockClaudeService.nextProcessResult = claudeError
        mockClaudeService.nextIsConnected = true

        let testPrompt = ClaudePrompt(id: UUID(), name: "Test", prompt: "Polish")
        mockClaudePromptManager.setTestPrompts([testPrompt])
        viewModel.fileClaudePromptID = testPrompt.id

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: true
        )

        // Then
        XCTAssertTrue(
            viewModel.consoleOutput.contains("⚠️ Claude processing failed"),
            "Should log Claude error"
        )

        // Verify output file contains raw transcription (fallback), not error
        let outputFile = audioURL.deletingPathExtension().appendingPathExtension("txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertEqual(
            content,
            rawTranscription,
            "Should fallback to raw transcription when Claude returns error"
        )
    }

    func testMarksClaudeServiceAsDisconnectedOnError() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "claude-disconnect.mp3")
        mockTranscriptionEngine.nextTranscription = "Some text"

        viewModel.fileClaudeEnabled = true
        mockClaudeService.nextProcessResult = "Fatal: authentication failed"
        mockClaudeService.nextIsConnected = true

        let testPrompt = ClaudePrompt(id: UUID(), name: "Test", prompt: "Polish")
        mockClaudePromptManager.setTestPrompts([testPrompt])
        viewModel.fileClaudePromptID = testPrompt.id

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: true
        )

        // Then
        XCTAssertFalse(
            mockClaudeService.isConnected,
            "Should mark Claude service as disconnected on error"
        )
    }

    // MARK: - Cancellation handling

    func testHandlesCancellationBeforeClaudeProcessingStarts() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "cancel-before-claude.mp3")
        mockTranscriptionEngine.nextTranscription = "Transcribed content"

        viewModel.fileClaudeEnabled = true
        mockClaudeService.nextProcessResult = "Should not be used"
        mockClaudeService.cancellationDelay = 0.01  // Inject delay to allow cancel

        let testPrompt = ClaudePrompt(id: UUID(), name: "Test", prompt: "Polish")
        mockClaudePromptManager.setTestPrompts([testPrompt])
        viewModel.fileClaudePromptID = testPrompt.id

        // When
        let processTask = Task {
            await runProcessAudio(
                fileURL: audioURL,
                model: .base,
                format: "txt",
                useClaude: true
            )
        }

        // Cancel during potential Claude processing
        try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
        viewModel.cancelTranscription()

        await processTask.value

        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(viewModel.consoleOutput.contains("❌ Transcription cancelled"))
    }

    func testHandlesCancellationDuringClaudeStream() async throws {
        // Given
        let audioURL = createTestAudioFile(name: "cancel-during-claude.mp3")
        mockTranscriptionEngine.nextTranscription = "Transcribed content for streaming test"

        viewModel.fileClaudeEnabled = true

        // Claude service will stream slowly to allow cancellation mid-stream
        mockClaudeService.nextProcessResult = "This is a long response that will be streamed chunk by chunk to simulate streaming behavior"
        mockClaudeService.streamingDelay = 0.05  // 50ms between chunks

        let testPrompt = ClaudePrompt(id: UUID(), name: "Test", prompt: "Polish")
        mockClaudePromptManager.setTestPrompts([testPrompt])
        viewModel.fileClaudePromptID = testPrompt.id

        // When
        let processTask = Task {
            await runProcessAudio(
                fileURL: audioURL,
                model: .base,
                format: "txt",
                useClaude: true
            )
        }

        // Let it start streaming, then cancel
        try await Task.sleep(nanoseconds: 30_000_000)  // 30ms
        viewModel.cancelTranscription()

        await processTask.value

        // Then
        XCTAssertFalse(viewModel.isProcessing)
    }

    // MARK: - File I/O error handling

    func testHandlesFileWriteErrorGracefully() async throws {
        // Given: Create audio file in a directory that will be deleted to cause write error
        let audioURL = tempDir.appendingPathComponent("test.mp3")
        try "fake audio".write(to: audioURL, atomically: true, encoding: .utf8)

        mockTranscriptionEngine.nextTranscription = "Test transcription"

        viewModel.fileClaudeEnabled = false

        // Delete the directory to cause file operations to fail
        try FileManager.default.removeItem(at: tempDir)

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: false
        )

        // Then
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(
            viewModel.consoleOutput.contains("❌ Error"),
            "Should log error when file write fails"
        )
    }

    func testDoesNotOverwriteExistingOutputFile() async throws {
        // Given: an output file already exists next to the input (e.g. the user's own
        // hand-edited transcript from a prior run).
        let audioURL = createTestAudioFile(name: "overwrite-test.mp3")
        let oldOutput = audioURL.deletingPathExtension().appendingPathExtension("txt")
        let oldContent = "Old content that should NOT be replaced"
        try oldContent.write(to: oldOutput, atomically: true, encoding: .utf8)

        let newTranscription = "New transcription content"
        mockTranscriptionEngine.nextTranscription = newTranscription

        viewModel.fileClaudeEnabled = false

        // When
        await runProcessAudio(
            fileURL: audioURL,
            model: .base,
            format: "txt",
            useClaude: false
        )

        // Then: the pre-existing file is untouched, and the new transcription lands
        // alongside it under a uniquified name instead of silently clobbering it (R8/U19).
        let preservedContent = try String(contentsOf: oldOutput, encoding: .utf8)
        XCTAssertEqual(preservedContent, oldContent)

        let uniquifiedOutput = audioURL.deletingLastPathComponent()
            .appendingPathComponent("overwrite-test 2.txt")
        let newContent = try String(contentsOf: uniquifiedOutput, encoding: .utf8)
        XCTAssertEqual(newContent, newTranscription)
        XCTAssertTrue(viewModel.consoleOutput.contains("✅ Transcription saved"))
    }

    // MARK: - Format support

    func testSupportsMultipleOutputFormats() async throws {
        for format in ["txt", "srt", "json"] {
            // Given
            let audioURL = createTestAudioFile(name: "format-test-\(format).mp3")
            mockTranscriptionEngine.nextTranscription = "Test in \(format)"

            viewModel.fileClaudeEnabled = false

            // When
            await runProcessAudio(
                fileURL: audioURL,
                model: .base,
                format: format,
                useClaude: false
            )

            // Then
            let outputFile = audioURL.deletingPathExtension().appendingPathExtension(format)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: outputFile.path),
                "Should create output file with .\\(format) extension"
            )
        }
    }

    // MARK: - Helper methods

    private func createTestAudioFile(name: String) -> URL {
        let audioURL = tempDir.appendingPathComponent(name)
        try? "fake audio data".write(to: audioURL, atomically: true, encoding: .utf8)
        return audioURL
    }

    private func runProcessAudio(
        fileURL: URL,
        model: Model,
        format: String,
        useClaude: Bool
    ) async {
        viewModel.transcribe(url: fileURL, model: model, format: format, useClaude: useClaude)

        // transcribe() spawns its work in a new Task and returns immediately, so
        // isProcessing may not have flipped true yet. Yield once to let that Task
        // start before polling for completion — otherwise a fast poll can race
        // ahead of the Task and see isProcessing still false, exiting immediately.
        await Task.yield()

        let startTime = Date()
        while viewModel.isProcessing && Date().timeIntervalSince(startTime) < 5.0 {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms poll interval
        }
    }
}

// MARK: - Mock Services

@MainActor
class ContentMockWhisperTranscriptionEngine: WhisperTranscriptionEngine {
    var nextTranscription: String = ""

    override func transcribeFormatted(
        audioURL: URL,
        model: Model,
        format: String,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> String {
        return nextTranscription
    }
}

@MainActor
class ContentMockClaudeService: ClaudeService {
    var nextProcessResult: String = ""
    var wasProcessCalled: Bool = false
    var lastProcessedPrompt: String?
    var lastProcessedText: String?
    var nextIsConnected: Bool = true
    var cancellationDelay: TimeInterval = 0
    var streamingDelay: TimeInterval = 0

    override func process(
        text: String,
        prompt: String,
        model: String = "sonnet"
    ) -> AsyncStream<String> {
        wasProcessCalled = true
        lastProcessedText = text
        lastProcessedPrompt = prompt
        isConnected = nextIsConnected

        return AsyncStream { continuation in
            Task {
                if self.cancellationDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(self.cancellationDelay * 1_000_000_000))
                }

                if self.streamingDelay > 0 {
                    // Stream the result in chunks
                    let words = self.nextProcessResult.split(separator: " ")
                    for word in words {
                        if Task.isCancelled { break }
                        continuation.yield(String(word) + " ")
                        try? await Task.sleep(nanoseconds: UInt64(self.streamingDelay * 1_000_000_000))
                    }
                } else {
                    continuation.yield(self.nextProcessResult)
                }

                continuation.finish()
            }
        }
    }
}

@MainActor
class ContentMockClaudePromptManager: ClaudePromptManager {
    private var testPrompts: [ClaudePrompt] = []

    func setTestPrompts(_ prompts: [ClaudePrompt]) {
        testPrompts = prompts
    }

    override var allPrompts: [ClaudePrompt] {
        return testPrompts.isEmpty ? ClaudePrompt.builtins : testPrompts
    }
}
