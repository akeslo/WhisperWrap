import FluidAudio
import Foundation

/// Which ASR backend dictation uses. File transcription always stays on WhisperKit.
enum DictationEngine: String, CaseIterable, Identifiable {
    case whisper = "Whisper"
    case parakeet = "Parakeet"
    var id: String { rawValue }
}

/// FluidAudio Parakeet TDT 0.6b v3 (parakeet-tdt-0.6b-v3-coreml), loaded once and reused.
@MainActor
final class ParakeetEngine {
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    var isReady: Bool { manager != nil }

    func prepare() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task<AsrManager, Error> {
            LoggerService.shared.debug("Loading Parakeet TDT v3")
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let m = AsrManager()
            try await m.loadModels(models)
            LoggerService.shared.debug("Parakeet ready")
            return m
        }
        loading = task
        defer { loading = nil }
        let m = try await task.value
        manager = m
        return m
    }

    func transcribe(audioURL: URL) async throws -> String {
        let m = try await prepare()
        var state = TdtDecoderState.make()
        return try await m.transcribe(audioURL, decoderState: &state).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
