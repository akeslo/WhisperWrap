import Foundation
import WhisperKit
import os.log

private let logger = Logger(subsystem: "com.whisperwrap", category: "WhisperTranscriptionEngine")

@MainActor
class WhisperTranscriptionEngine: ObservableObject {
    @Published var isReady = false
    @Published var downloadProgress: Double = 0

    private var pipe: WhisperKit?
    private var loadedModelName: String?
    private var loadingTask: Task<Void, Never>?
    private var loadError: Error?

    // Load/download model. Deduplicates concurrent calls.
    func prepareModel(_ model: Model) async throws {
        let modelName = model.whisperKitModelName

        if loadedModelName == modelName, pipe != nil {
            isReady = true
            return
        }

        if let existing = loadingTask {
            await existing.value
            if let err = loadError { throw err }
            return
        }

        loadError = nil
        let task = Task { @MainActor in
            do {
                self.isReady = false
                self.downloadProgress = 0
                logger.info("Downloading model: \(modelName)")

                let modelFolder = try await WhisperKit.download(variant: modelName) { @Sendable progress in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                }

                let newPipe = try await WhisperKit(modelFolder: modelFolder.path)
                self.pipe = newPipe
                self.loadedModelName = modelName
                self.isReady = true
                self.downloadProgress = 1.0
                logger.info("Model ready: \(modelName)")
            } catch {
                logger.error("Model load failed: \(error)")
                self.loadError = error
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
        if let err = loadError { throw err }
    }

    // Transcribe audio file to plain text (for dictation).
    func transcribeToText(audioURL: URL, model: Model, onProgress: ((Double) -> Void)? = nil) async throws -> String {
        try await prepareModel(model)
        guard let pipe else { throw TranscriptionError.notReady }

        let results = try await pipe.transcribe(audioPath: audioURL.path)
        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "" : text
    }

    // Transcribe and format for file output (txt / srt / json).
    func transcribeFormatted(
        audioURL: URL,
        model: Model,
        format: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> String {
        try await prepareModel(model)
        guard let pipe else { throw TranscriptionError.notReady }

        let results = try await pipe.transcribe(audioPath: audioURL.path)
        let allSegments = results.flatMap { $0.segments }

        switch format {
        case "srt":
            var lines: [String] = []
            for (i, seg) in allSegments.enumerated() {
                lines.append("\(i + 1)")
                lines.append("\(formatSRTTime(seg.start)) --> \(formatSRTTime(seg.end))")
                lines.append(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
            return lines.joined(separator: "\n")

        case "json":
            let jsonLines = allSegments.map { seg -> String in
                let escaped = seg.text.replacingOccurrences(of: "\"", with: "\\\"")
                return "{\"start\":\(seg.start),\"end\":\(seg.end),\"text\":\"\(escaped)\"}"
            }
            return jsonLines.joined(separator: "\n")

        default: // "txt"
            return allSegments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func formatSRTTime(_ seconds: Float) -> String {
        let total = Int(seconds)
        let ms = Int((seconds - Float(total)) * 1000)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

enum TranscriptionError: Error {
    case notReady
}
