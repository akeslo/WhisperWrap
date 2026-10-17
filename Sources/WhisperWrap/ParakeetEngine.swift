import FluidAudio
import Foundation

/// FluidAudio Parakeet TDT 0.6b v3 (parakeet-tdt-0.6b-v3-coreml), loaded once and reused.
/// Used for both dictation and file transcription. Not final so tests can mock it.
@MainActor
class ParakeetEngine {
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
        try await transcribeResult(audioURL: audioURL).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeResult(audioURL: URL) async throws -> ASRResult {
        let m = try await prepare()
        var state = TdtDecoderState.make()
        return try await m.transcribe(audioURL, decoderState: &state)
    }

    /// Transcribe and format for file output (txt / srt / json).
    func transcribeFormatted(audioURL: URL, format: String) async throws -> String {
        let r = try await transcribeResult(audioURL: audioURL)
        let segs = Self.segments(
            tokens: (r.tokenTimings ?? []).map { ($0.token, Float($0.startTime), Float($0.endTime)) },
            fallbackText: r.text, duration: Float(r.duration))
        return try Self.format(segments: segs, as: format)
    }

    /// Groups Parakeet token timings into caption segments: break after sentence-ending
    /// punctuation or before a pause > `pause` seconds. No timings → one segment spanning
    /// the whole duration. Tokens are SentencePiece pieces ("▁" marks a word start).
    static func segments(tokens: [(text: String, start: Float, end: Float)],
                         fallbackText: String, duration: Float, pause: Float = 0.8) -> [ExportedSegment] {
        let fallback = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tokens.isEmpty else {
            return fallback.isEmpty ? [] : [ExportedSegment(start: 0, end: duration, text: fallback)]
        }
        var out: [ExportedSegment] = []
        var text = "", start = tokens[0].start, end = tokens[0].start
        func flush() {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(ExportedSegment(start: start, end: end, text: t)) }
            text = ""
        }
        for tok in tokens {
            if !text.isEmpty, tok.start - end > pause { flush() }
            if text.isEmpty { start = tok.start }
            text += tok.text.replacingOccurrences(of: "▁", with: " ")
            end = tok.end
            if let last = tok.text.trimmingCharacters(in: .whitespaces).last, ".?!".contains(last) { flush() }
        }
        flush()
        return out
    }

    /// A transcription segment decoupled from FluidAudio's types, so the pure formatting
    /// logic below can be tested without a loaded model.
    struct ExportedSegment: Encodable, Equatable {
        let start: Float
        let end: Float
        let text: String
    }

    /// Pure formatting of transcribed segments into txt/srt/json. Fixes R7: json used to be
    /// hand-rolled interpolation producing invalid JSON/JSONL; now JSONEncoder, a JSON array.
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
