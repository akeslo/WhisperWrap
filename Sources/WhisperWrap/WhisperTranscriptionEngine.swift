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
    private var loadingModelName: String?
    private var loadError: Error?

    // Load/download model. Deduplicates concurrent calls.
    func prepareModel(_ model: Model) async throws {
        let modelName = model.whisperKitModelName

        if loadedModelName == modelName, pipe != nil {
            isReady = true
            return
        }

        // Only join an in-flight load when it is loading the *same* model.
        // A different model must wait for that load to finish, then start its
        // own — otherwise the caller would silently transcribe with the wrong model.
        while let existing = loadingTask {
            let inFlightModelName = loadingModelName
            await existing.value
            if inFlightModelName == modelName {
                if let err = loadError { throw err }
                return
            }
            if loadedModelName == modelName, pipe != nil {
                isReady = true
                return
            }
        }

        loadError = nil
        loadingModelName = modelName
        let task = Task { @MainActor in
            do {
                self.isReady = false
                self.downloadProgress = 0
                logger.info("Downloading model: \(modelName)")
                LoggerService.shared.debug("Downloading WhisperKit model: \(modelName)")

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
                LoggerService.shared.debug("Model ready: \(modelName)")
            } catch {
                logger.error("Model load failed: \(error)")
                LoggerService.shared.debug("Model load failed: \(error.localizedDescription)")
                self.loadError = error
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
        loadingModelName = nil
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
            .map { ExportedSegment(start: $0.start, end: $0.end, text: $0.text) }
        return try Self.format(segments: allSegments, as: format)
    }

    /// A transcription segment decoupled from WhisperKit's own segment type, so the pure
    /// formatting logic below can be tested without a loaded model.
    struct ExportedSegment: Encodable {
        let start: Float
        let end: Float
        let text: String
    }

    /// Pure formatting of transcribed segments into txt/srt/json — extracted so it can be
    /// unit tested without WhisperKit. Fixes R7: the json case used to be hand-rolled string
    /// interpolation that only escaped `"`, producing invalid JSON for any transcript
    /// containing a backslash, newline, or other control character, and emitted JSONL under
    /// a ".json" extension. Now uses JSONEncoder and emits a proper JSON array.
    static func format(segments: [ExportedSegment], as format: String) throws -> String {
        switch format {
        case "srt":
            var lines: [String] = []
            for (i, seg) in segments.enumerated() {
                lines.append("\(i + 1)")
                lines.append("\(formatSRTTime(seg.start)) --> \(formatSRTTime(seg.end))")
                lines.append(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
            }
            return lines.joined(separator: "\n")

        case "json":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(segments)
            return String(data: data, encoding: .utf8) ?? "[]"

        default: // "txt"
            return segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func formatSRTTime(_ seconds: Float) -> String {
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
