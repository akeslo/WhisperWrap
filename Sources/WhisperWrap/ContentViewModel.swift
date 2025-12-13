import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

@MainActor
class ContentViewModel: ObservableObject {
    @Published var whisperInstalled: Bool = false
    @Published var installationOutput: String = ""
    @Published var isInstalling: Bool = false
    @Published var isCheckingEnv: Bool = false
    // legacy flag retained for compatibility; no longer used
    @Published var homebrewNotInstalledError: Bool = false
    @Published var consoleOutput: String = ""
    @Published var isProcessing: Bool = false
    @Published var processingStage: String = ""
    @Published var processingProgress: Double = 0.0
    @Published var requestedTab: Int? = nil

    let shellService = ShellService()
    private lazy var pythonEnv = PythonEnvManager(applicationSupportDirectory: applicationSupportDirectory, shell: shellService)
    private var cancellables = Set<AnyCancellable>()
    private var processingTask: Task<Void, Never>?
    
    // Derived state for launch logic
    var needsSetup: Bool {
        return !whisperInstalled && !isCheckingEnv
    }
    
    private let applicationSupportDirectory: URL = {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperWrap")
    }()

    init() {
        checkDependencies()
        cleanupOldTempFiles()
    }

    func checkDependencies() {
        isCheckingEnv = true
        Task {
            LoggerService.shared.debug("🔍 Checking embedded Python env...")
            let ready = await pythonEnv.isReady()
            self.whisperInstalled = ready
            self.homebrewNotInstalledError = false
            LoggerService.shared.debug("✅ faster-whisper ready: \(ready)")
            self.isCheckingEnv = false
        }
    }

    // Removed Homebrew installer; embedded env is used instead.

    func installDependencies() {
        // Prevent duplicate setup while checking or if already installed
        if isCheckingEnv { return }
        if whisperInstalled {
            installationOutput = "Already installed."
            return
        }
        isInstalling = true
        installationOutput = ""
        homebrewNotInstalledError = false

        LoggerService.shared.debug("📦 Setting up embedded speech engine (venv + faster-whisper)...")

        Task {
            let stream = pythonEnv.setup()
            for await output in stream {
                LoggerService.shared.debug("📦 Setup output: \(output)")
                DispatchQueue.main.async {
                    self.installationOutput += output
                }
            }

            DispatchQueue.main.async {
                self.isInstalling = false
                LoggerService.shared.debug("🔄 Re-checking env...")
                self.checkDependencies()
            }
        }
    }
    
    func transcribe(url: URL, model: Model, format: String) {
        processAudio(fileURL: url, model: model, format: format)
    }
    
    func transcribeDictation(audioURL: URL, model: Model) async throws -> String {
        // Ensure model is ready (using base model for dictation speed/quality balance)
        // Convert to compatible format if needed? runWhisper handles it.
        
        let outputURL = try await runWhisper(on: audioURL, model: model, format: "txt", testMode: false)
        
        // Read the content
        let transcription = try String(contentsOf: outputURL, encoding: .utf8)
        
        // Clean up
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(at: outputURL)
        
        return transcription
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
                if securityScoped {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                // Show temp directory location
                let tempDir = FileManager.default.temporaryDirectory
                consoleOutput += "📁 Temp directory: \(tempDir.path)\n\n"

                // faster-whisper accepts all audio formats directly - no conversion needed!
                let fileExtension = fileURL.pathExtension.lowercased()

                processingStage = "Initializing..."
                processingProgress = 0.1
                consoleOutput += "📄 Input File: \(fileURL.lastPathComponent)\n"
                consoleOutput += "🎵 Format: \(fileExtension.uppercased()) (Native Support)\n\n"

                processingStage = "Transcribing..."
                processingProgress = 0.3
                consoleOutput += "🎙️ Model: \(model.displayName)\n"
                consoleOutput += "📄 Output: \(format.uppercased())\n"
                consoleOutput += "🚀 Acceleration: Auto (GPU/CPU)\n\n"
                let outputURL = try await runWhisper(on: fileURL, model: model, format: format, testMode: false)

                processingStage = "Saving transcription..."
                processingProgress = 0.9
                consoleOutput += "\n💾 Saving transcription...\n"
                
                // User requested saving to input file's directory
                let inputDir = fileURL.deletingLastPathComponent()
                let finalURL = inputDir.appendingPathComponent(outputURL.lastPathComponent)

                // If file exists, try to replace or rename? For now, let's just move.
                // Note: Sandbox might prevent writing to input dir if we only have file-scoped access.
                // If it fails, we fall back to logging the error.
                
                // If destination exists, remove it first
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                
                try FileManager.default.moveItem(at: outputURL, to: finalURL)

                processingProgress = 1.0
                consoleOutput += "✅ Transcription saved to: \(finalURL.path)\n"

                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([finalURL])
                #endif

            } catch {
                consoleOutput += "\n❌ Error: \(error.localizedDescription)\n"
                LoggerService.shared.debug("Transcription Process Error: \(error)")
            }
        }
    }
    
    private func preprocessAudio(for url: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("\(UUID().uuidString).flac")

        let command = "ffmpeg -nostdin -y -stats -i \"\(url.path)\" -ar 16000 -ac 1 -c:a flac \"\(outputURL.path)\" 2>&1"

        let stream = shellService.streamCommand(command)
        var lastProgressLine = ""

        for await output in stream {
            DispatchQueue.main.async {
                // Handle carriage returns for progress updates
                if output.contains("\r") {
                    let lines = output.components(separatedBy: "\r")
                    // Show non-progress lines immediately
                    for (index, line) in lines.enumerated() where !line.isEmpty {
                        if line.contains("time=") {
                            // This is a progress line - save it to only show the latest
                            lastProgressLine = line
                            if index == lines.count - 1 {
                                // Last line, show it
                                self.consoleOutput += lastProgressLine + "\n"
                            }
                        } else {
                            // Non-progress line, show immediately
                            self.consoleOutput += line + "\n"
                        }
                    }
                } else {
                    // No carriage return, show everything
                    self.consoleOutput += output
                }
            }
        }

        // Verify the output file was created
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(domain: "WhisperWrap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create FLAC file"])
        }

        return outputURL
    }
    
    private func runWhisper(on url: URL, model: Model, format: String, testMode: Bool) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent)

        // faster-whisper uses model names directly, not file paths
        // Model size mapping: tiny, base, small, medium, large
        let modelSize = model.fasterWhisperName

        // Set cache path for model storage
        let cachePath = applicationSupportDirectory.appendingPathComponent("models").path.replacingOccurrences(of: "\"", with: "\\\"")

        // faster-whisper accepts any audio format directly (MP3, M4A, WAV, etc.)
        let command: String
        if testMode {
            // In test mode, just check if faster-whisper can load the file
            command = "\"\(pythonEnv.pythonPath)\" -c \"import os; os.environ['HF_HUB_CACHE'] = '\(cachePath)'; from faster_whisper import WhisperModel; import sys; model = WhisperModel('" + modelSize + "', device='auto', compute_type='int8'); segments, info = model.transcribe('" + url.path.replacingOccurrences(of: "\"", with: "\\\"") + "', beam_size=1); next(segments, None); print('OK')\""
        } else {
            // Use faster-whisper via embedded Python for transcription
            let outputFormat = format == "srt" ? "srt" : (format == "json" ? "json" : "txt")
            let inputPath = url.path.replacingOccurrences(of: "\"", with: "\\\"")
            // Use .path to avoid URL encoding issues (e.g. %20)
            let outputBasePath = outputPath.path.replacingOccurrences(of: "\"", with: "\\\"")

            command = """
            \"\(pythonEnv.pythonPath)\" -c "
            import os
            os.environ['HF_HUB_CACHE'] = '\(cachePath)'
            from faster_whisper import WhisperModel
            import sys
            import math

            model = WhisperModel('\(modelSize)', device='auto', compute_type='int8')
            segments, info = model.transcribe('\(inputPath)')

            output = []
            
            # Duration in seconds
            duration = info.duration
            
            for i, segment in enumerate(segments):
                if '\(outputFormat)' == 'srt':
                    output.append(f'{i+1}')
                    output.append(f'{segment.start:.3f} --> {segment.end:.3f}')
                    output.append(segment.text.strip())
                    output.append('')
                elif '\(outputFormat)' == 'json':
                    import json
                    output.append(json.dumps({'start': segment.start, 'end': segment.end, 'text': segment.text}))
                else:
                    output.append(segment.text.strip())
                
                # Calculate progress
                if duration > 0:
                    prog = int((segment.end / duration) * 100)
                    print(f'Progress: {prog}', file=sys.stderr)
                    sys.stderr.flush()

            join_char = '\\n'
            if '\(outputFormat)' == 'txt':
                join_char = ' '
            
            with open('\(outputBasePath).\(format)', 'w') as f:
                f.write(join_char.join(output))
            print('Done')
            "
            """
        }

        let stream = shellService.streamCommand(command)
        var errorOutput = ""
        var firstLineShown = false

        for await output in stream {
            // Check if task was cancelled
            if Task.isCancelled {
                break
            }

            if testMode {
                // In test mode, show first few lines for feedback, then check for errors
                errorOutput += output
                if !firstLineShown && !output.isEmpty {
                    DispatchQueue.main.async {
                        self.consoleOutput += "   \(output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first ?? "")\n"
                    }
                    firstLineShown = true
                }
            } else {
                // Check if it's a progress update
                if output.contains("Progress:") {
                    let comps = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "Progress: ")
                    if let last = comps.last, let prog = Double(last) {
                        DispatchQueue.main.async {
                            // Map 0-100 to 0.1-0.9 range (keeping 0.1 for start and leaving room for save)
                            let uiProg = 0.1 + (prog / 100.0 * 0.8)
                            self.processingProgress = min(uiProg, 0.99)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.consoleOutput += output
                    }
                }
            }
        }

        // If cancelled, throw to exit early
        if Task.isCancelled {
            throw CancellationError()
        }

        // In test mode, check if there were any errors
        if testMode {
            if errorOutput.lowercased().contains("error") || errorOutput.lowercased().contains("traceback") {
                throw NSError(domain: "WhisperWrap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Format not compatible"])
            }
            return tempDir // Return dummy URL in test mode
        }

        // Return the output file path
        // FIX: Ensure we return a valid URL pointing to the file path, not string interpolating the URL object itself.
        return outputPath.appendingPathExtension(format)
    }

    // MARK: - Diagnostics helpers
    var embeddedPythonPath: String { pythonEnv.pythonPath }
    var embeddedVenvPath: String { pythonEnv.venvPath.path }
    func runShell(_ cmd: String) async throws -> String { try await shellService.runCommand(cmd) }

    private func cleanupOldTempFiles() {
        Task {
            let tempDir = FileManager.default.temporaryDirectory
            let fileManager = FileManager.default

            do {
                let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)

                // Clean up old FLAC files and transcription files from previous runs
                for fileURL in contents {
                    let filename = fileURL.lastPathComponent

                    // Remove old temp FLAC files (UUID pattern)
                    if filename.hasSuffix(".flac") && filename.count == 41 { // UUID.flac = 36 chars + 5 for .flac
                        try? fileManager.removeItem(at: fileURL)
                    }

                    // Remove old temp transcription outputs
                    if filename.hasSuffix(".txt") || filename.hasSuffix(".srt") || filename.hasSuffix(".json") {
                        // Check if file is older than 1 hour to avoid removing files from active sessions
                        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                           let creationDate = attributes[.creationDate] as? Date,
                           Date().timeIntervalSince(creationDate) > 3600 {
                            try? fileManager.removeItem(at: fileURL)
                        }
                    }
                }
            } catch {
                // Silently ignore cleanup errors
                LoggerService.shared.debug("⚠️ Temp file cleanup warning: \(error)")
            }
        }
    }
}
