import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
class ContentViewModel: ObservableObject {
    // No more whisperInstalled / isInstalling / isCheckingEnv
    // WhisperKit downloads models on first use automatically
    @Published var consoleOutput: String = ""
    @Published var isProcessing: Bool = false
    @Published var processingStage: String = ""
    @Published var processingProgress: Double = 0.0
    @Published var requestedTab: Int? = nil

    // Claude Processing Settings (file transcription)
    @Published var fileClaudeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(fileClaudeEnabled, forKey: "fileClaudeEnabled") }
    }
    @Published var fileClaudePromptID: UUID? {
        didSet {
            if let id = fileClaudePromptID {
                UserDefaults.standard.set(id.uuidString, forKey: "fileClaudePromptID")
            } else {
                UserDefaults.standard.removeObject(forKey: "fileClaudePromptID")
            }
        }
    }
    @Published var claudeStreamingOutput: String = ""

    var claudeService: ClaudeService?
    var claudePromptManager: ClaudePromptManager?

    let transcriptionEngine: WhisperTranscriptionEngine
    private var processingTask: Task<Void, Never>?

    // Always ready — no Python setup needed
    var needsSetup: Bool { false }

    var logCount: Int { LoggerService.shared.logs.count }
    var recentLogs: String {
        let all = LoggerService.shared.logs
        let recent = all.suffix(50)
        return recent.joined(separator: "\n")
    }

    init(transcriptionEngine: WhisperTranscriptionEngine? = nil) {
        self.transcriptionEngine = transcriptionEngine ?? WhisperTranscriptionEngine()
        self.fileClaudeEnabled = UserDefaults.standard.bool(forKey: "fileClaudeEnabled")
        if let savedID = UserDefaults.standard.string(forKey: "fileClaudePromptID"),
           let uuid = UUID(uuidString: savedID) {
            self.fileClaudePromptID = uuid
        } else {
            self.fileClaudePromptID = ClaudePrompt.builtinPolish.id
        }
        cleanupOldTempFiles()
    }

    func transcribe(url: URL, model: Model, format: String, useClaude: Bool) {
        processAudio(fileURL: url, model: model, format: format, useClaude: useClaude)
    }

    func transcribeDictation(audioURL: URL, model: Model) async throws -> String {
        let text = try await transcriptionEngine.transcribeToText(audioURL: audioURL, model: model, onProgress: nil)
        try? FileManager.default.removeItem(at: audioURL)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.noSpeechDetectedSentinel
        }
        return text
    }

    /// Display-only sentinel for a take that produced no transcribable speech. Never
    /// auto-copied — see the autoCopy guard in DictationViewModel (U4).
    static let noSpeechDetectedSentinel = "No Speech Detected"

    func cancelTranscription() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        processingStage = ""
        processingProgress = 0.0
        consoleOutput += "\n❌ Transcription cancelled\n"
    }

    private func processAudio(fileURL: URL, model: Model, format: String, useClaude: Bool) {
        processingTask = Task {
            isProcessing = true
            consoleOutput = ""
            processingProgress = 0.0
            defer {
                isProcessing = false
                processingTask = nil
                processingStage = ""
                processingProgress = 0.0
            }

            let securityScoped = fileURL.startAccessingSecurityScopedResource()
            defer {
                if securityScoped { fileURL.stopAccessingSecurityScopedResource() }
            }

            do {
                let fileExtension = fileURL.pathExtension.lowercased()
                processingStage = "Initializing..."
                processingProgress = 0.1
                consoleOutput += "📄 Input File: \(fileURL.lastPathComponent)\n"
                consoleOutput += "🎵 Format: \(fileExtension.uppercased())\n\n"

                processingStage = "Transcribing..."
                consoleOutput += "🎙️ Model: \(model.displayName)\n"
                consoleOutput += "📄 Output: \(format.uppercased())\n"
                consoleOutput += "🚀 Acceleration: CoreML / Apple Neural Engine\n\n"

                let transcribedText = try await transcriptionEngine.transcribeFormatted(
                    audioURL: fileURL,
                    model: model,
                    format: format
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.processingProgress = 0.1 + progress * 0.8
                    }
                }

                if Task.isCancelled { return }

                // Write to temp file then move to input dir
                let tempDir = try Self.ensureScratchDirectory()
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let tempOutputURL = tempDir.appendingPathComponent("\(baseName).\(format)")
                try transcribedText.write(to: tempOutputURL, atomically: true, encoding: .utf8)

                // Claude processing (if enabled explicitly for this file)
                if useClaude,
                   let claudeService = claudeService,
                   let claudePromptManager = claudePromptManager,
                   let promptID = fileClaudePromptID,
                   let prompt = claudePromptManager.allPrompts.first(where: { $0.id == promptID }) {

                    if transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        consoleOutput += "⚠️ Transcription was empty, skipping Claude processing\n"
                    } else {
                        processingStage = "Processing with Claude..."
                        consoleOutput += "\n🧠 Processing with Claude (\(prompt.name))...\n"
                        claudeStreamingOutput = ""

                        let claudeModel = UserDefaults.standard.string(forKey: "dictationClaudeModel") ?? "sonnet"
                        let stream = claudeService.process(text: transcribedText, prompt: prompt.prompt, model: claudeModel)
                        var streamedResult = ""
                        for await chunk in stream {
                            // Return, not break: breaking falls through to the save
                            // block below and writes partial Claude output next to the
                            // input file (and reveals it in Finder) after a cancel.
                            if Task.isCancelled { return }
                            streamedResult += chunk
                            claudeStreamingOutput = streamedResult
                        }

                        let trimmed = streamedResult.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !ClaudeService.looksLikeError(trimmed) {
                            try trimmed.write(to: tempOutputURL, atomically: true, encoding: .utf8)
                            consoleOutput += "✅ Claude processing complete\n"
                        } else if ClaudeService.looksLikeError(trimmed) {
                            claudeService.isConnected = false
                            consoleOutput += "⚠️ Claude processing failed, using raw transcription\n"
                        } else {
                            // Empty stdout, no recognizable error text — e.g. the `claude`
                            // CLI isn't on PATH. Silently shipping the raw transcription
                            // with no console line is exactly R6 (DEFERRED.md); surface it
                            // and flip isConnected the same way the error branch does.
                            claudeService.isConnected = false
                            consoleOutput += "⚠️ Claude produced no output (CLI missing or misconfigured?), using raw transcription\n"
                        }
                        claudeStreamingOutput = ""
                    }
                }

                processingStage = "Saving transcription..."
                processingProgress = 0.9
                consoleOutput += "\n💾 Saving transcription...\n"

                let inputDir = fileURL.deletingLastPathComponent()
                let finalURL = Self.uniqueDestination(
                    for: tempOutputURL.lastPathComponent,
                    in: inputDir
                )
                try FileManager.default.moveItem(at: tempOutputURL, to: finalURL)

                processingProgress = 1.0
                consoleOutput += "✅ Transcription saved to: \(finalURL.path)\n"

                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                #endif

            } catch {
                consoleOutput += "\n❌ Error: \(error.localizedDescription)\n"
                LoggerService.shared.debug("Transcription error: \(error)")
            }
        }
    }

    /// Scratch directory for transcription output staged before the move next to the
    /// input file. Must be a WhisperWrap-owned subdirectory, never the shared temp dir
    /// itself: `cleanupOldTempFiles()` deletes by extension, and pointed at the shared
    /// directory it would reap `.txt`/`.srt`/`.json` files belonging to other processes.
    static let scratchDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("WhisperWrap", isDirectory: true)

    private static func ensureScratchDirectory() throws -> URL {
        let dir = scratchDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Finds a non-colliding destination for `filename` inside `directory`, appending
    /// " 2", " 3", ... before the extension (matching Finder's own collision naming)
    /// rather than silently overwriting an existing file — including one the user has
    /// since edited by hand. (R8/U19)
    static func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (filename as NSString).pathExtension
        let base = (filename as NSString).deletingPathExtension
        var counter = 2
        while true {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let numberedURL = directory.appendingPathComponent(numbered)
            if !FileManager.default.fileExists(atPath: numberedURL.path) {
                return numberedURL
            }
            counter += 1
        }
    }

    private func cleanupOldTempFiles() {
        Task {
            let tempDir = Self.scratchDirectory
            let fileManager = FileManager.default
            do {
                let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                for fileURL in contents {
                    let filename = fileURL.lastPathComponent
                    if filename.hasSuffix(".txt") || filename.hasSuffix(".srt") || filename.hasSuffix(".json") || filename.hasSuffix(".wav") {
                        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                           let created = attrs[.creationDate] as? Date,
                           Date().timeIntervalSince(created) > 3600 {
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                }
            } catch {
                LoggerService.shared.debug("Temp file cleanup failed: \(error)")
            }
        }
    }
}
