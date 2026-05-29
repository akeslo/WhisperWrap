import AVFoundation
import FluidAudio
import Foundation

// Trims silence from a 16 kHz WAV recording before transcription.
// Returns URL of trimmed audio file, or nil if VAD fails / audio is all speech.
final class FluidVADProcessor: @unchecked Sendable {
    private static let sampleRate = 16000
    private static let threshold: Float = 0.5
    private static let mergeGapSeconds: TimeInterval = 0.3
    private static let minRegionSeconds: TimeInterval = 0.15

    func trimSilence(audioURL: URL) async -> URL? {
        do {
            let samples = try loadAsPCM(url: audioURL)
            guard samples.count > Self.sampleRate else { return nil } // < 1s, skip

            let config = VadConfig(defaultThreshold: Self.threshold)
            let manager = try await VadManager(config: config)
            let results = try await manager.process(samples)

            let regions = buildRegions(from: results)
            guard !regions.isEmpty else { return nil }

            // Skip VAD if it would trim less than 10% — not worth the overhead
            let totalSamples = samples.count
            let speechSampleCount = regions.reduce(0) { acc, r in
                acc + (Int(r.end * Double(Self.sampleRate)) - Int(r.start * Double(Self.sampleRate)))
            }
            let trimRatio = 1.0 - Double(speechSampleCount) / Double(totalSamples)
            guard trimRatio > 0.1 else { return nil }

            let speechSamples = extractSpeech(samples: samples, regions: regions)
            guard speechSamples.count > Self.sampleRate / 2 else { return nil }

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dictation_trimmed.wav")
            try writePCM(samples: speechSamples, to: outURL)
            return outURL
        } catch {
            return nil // VAD failure → caller uses original audio
        }
    }

    private func loadAsPCM(url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { return [] }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        // If the file is already at 16 kHz, read directly; otherwise convert
        if abs(audioFile.processingFormat.sampleRate - Double(Self.sampleRate)) < 1 {
            try audioFile.read(into: buffer)
        } else {
            // Use AVAudioConverter for non-16 kHz files
            let converter = AVAudioConverter(from: audioFile.processingFormat, to: format)
            let srcBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount)!
            try audioFile.read(into: srcBuffer)
            var error: NSError?
            converter?.convert(to: buffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return srcBuffer
            }
            if let e = error { throw e }
        }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    private func buildRegions(from results: [VadResult]) -> [(start: Double, end: Double)] {
        let chunkDuration = Double(VadManager.chunkSize) / Double(VadManager.sampleRate)
        var regions: [(start: Double, end: Double)] = []
        var speechStart: Double?

        for (index, result) in results.enumerated() {
            let chunkTime = Double(index) * chunkDuration
            if result.probability >= Self.threshold {
                if speechStart == nil { speechStart = chunkTime }
            } else if let start = speechStart {
                regions.append((start: start, end: chunkTime))
                speechStart = nil
            }
        }
        if let start = speechStart {
            regions.append((start: start, end: Double(results.count) * chunkDuration))
        }

        // Merge close regions
        var merged: [(start: Double, end: Double)] = []
        for region in regions {
            if let last = merged.last, region.start - last.end < Self.mergeGapSeconds {
                merged[merged.count - 1] = (start: last.start, end: region.end)
            } else {
                merged.append(region)
            }
        }

        return merged.filter { $0.end - $0.start >= Self.minRegionSeconds }
    }

    private func extractSpeech(samples: [Float], regions: [(start: Double, end: Double)]) -> [Float] {
        var result: [Float] = []
        for region in regions {
            let startIdx = Int(region.start * Double(Self.sampleRate))
            let endIdx = min(Int(region.end * Double(Self.sampleRate)), samples.count)
            guard startIdx < endIdx, startIdx < samples.count else { continue }
            result.append(contentsOf: samples[startIdx ..< endIdx])
        }
        return result
    }

    private func writePCM(samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].assign(from: ptr.baseAddress!, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
