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

    let transcriptionEngine = WhisperTranscriptionEngine()
    private var processingTask: Task<Void, Never>?

    // Always ready — no Python setup needed
    var needsSetup: Bool { false }

    init() {
        self.fileClaudeEnabled = UserDefaults.standard.bool(forKey: "fileClaudeEnabled")
        if let savedID = UserDefaults.standard.string(forKey: "fileClaudePromptID"),
           let uuid = UUID(uuidString: savedID) {
            self.fileClaudePromptID = uuid
        } else {
            self.fileClaudePromptID = ClaudePrompt.builtinPolish.id
        }
        cleanupOldTempFiles()
    }

    func transcribe(url: URL, model: Model, format: String) {
        processAudio(fileURL: url, model: model, format: format)
    }

    func transcribeDictation(audioURL: URL, model: Model) async throws -> String {
        let text = try await transcriptionEngine.transcribeToText(audioURL: audioURL, model: model, onProgress: nil)
        try? FileManager.default.removeItem(at: audioURL)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Speech Detected"
        }
        return text
    }

    func cancelTranscription() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        processingStage = ""
        processingProgress = 0.0
        consoleOutput += "\n❌ Transcription cancelled\n"
    }

    private func processAudio(fileURL: URL, model: Model, format: String) {
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
                let tempDir = FileManager.default.temporaryDirectory
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let tempOutputURL = tempDir.appendingPathComponent("\(baseName).\(format)")
                try transcribedText.write(to: tempOutputURL, atomically: true, encoding: .utf8)

                // Claude processing (if enabled)
                if fileClaudeEnabled,
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
                            if Task.isCancelled { break }
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
                        }
                        claudeStreamingOutput = ""
                    }
                }

                processingStage = "Saving transcription..."
                processingProgress = 0.9
                consoleOutput += "\n💾 Saving transcription...\n"

                let inputDir = fileURL.deletingLastPathComponent()
                let finalURL = inputDir.appendingPathComponent(tempOutputURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
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

    private func cleanupOldTempFiles() {
        Task {
            let tempDir = FileManager.default.temporaryDirectory
            let fileManager = FileManager.default
            do {
                let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                for fileURL in contents {
                    let filename = fileURL.lastPathComponent
                    if filename.hasSuffix(".txt") || filename.hasSuffix(".srt") || filename.hasSuffix(".json") {
                        if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                           let created = attrs[.creationDate] as? Date,
                           Date().timeIntervalSince(created) > 3600 {
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                }
            } catch {}
        }
    }
}
