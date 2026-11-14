@preconcurrency import AVFoundation
import FluidAudio
import Foundation

// Trims silence from a 16 kHz WAV recording before transcription.
// Returns URL of trimmed audio file, or nil if VAD fails / audio is all speech.
final class FluidVADProcessor: @unchecked Sendable {
    private static let sampleRate = 16000
    private static let threshold: Float = 0.5
    private static let mergeGapSeconds: TimeInterval = 0.3
    private static let minRegionSeconds: TimeInterval = 0.15

    /// A-SLOP-5: `loadAsPCM`/`writePCM` used to force-unwrap `AVAudioFormat`/`AVAudioPCMBuffer`
    /// allocation. Those inits *can* return nil (invalid format, huge frame count exhausting
    /// memory); a nil there force-crashed the whole app instead of reaching `trimSilence`'s
    /// existing `catch { return nil }` degrade-to-original-audio path. Now they throw this and
    /// let that path do its job.
    private enum VADAllocationError: Error {
        case formatCreationFailed
        case bufferAllocationFailed
    }

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

            // Route through the WhisperWrap-owned scratch directory, not the shared
            // per-user temp dir directly — matches the convention that already applies
            // to dictation.wav (fixed 2026-08-03), so a crash mid-transcription leaves
            // this file somewhere the app can find and reap it, not stray in shared temp
            // forever (REMEDIATION_PLAN.md R9 / A-SEC-6). Path literal duplicated from
            // ContentViewModel.scratchDirectory rather than referenced directly — that
            // property is @MainActor-isolated and this method isn't.
            let scratchDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WhisperWrap", isDirectory: true)
            try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
            let outURL = scratchDir.appendingPathComponent("dictation_trimmed.wav")
            try writePCM(samples: speechSamples, to: outURL)
            return outURL
        } catch {
            return nil // VAD failure → caller uses original audio
        }
    }

    /// Decodes `url` to 16 kHz mono Float32 samples, resampling other rates. Holds the whole
    /// take in memory twice (about 3.8 MB/min each); fine for dictation.
    func loadAsPCM(url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: false
        ) else { throw VADAllocationError.formatCreationFailed }
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { return [] }
        let buffer: AVAudioPCMBuffer
        let srcRate = audioFile.processingFormat.sampleRate
        // If the file is already at 16 kHz, read directly; otherwise convert
        if abs(srcRate - Double(Self.sampleRate)) < 1 {
            guard let direct = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw VADAllocationError.bufferAllocationFailed
            }
            try audioFile.read(into: direct)
            buffer = direct
        } else {
            guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: format) else {
                throw VADAllocationError.formatCreationFailed
            }
            guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                throw VADAllocationError.bufferAllocationFailed
            }
            try audioFile.read(into: srcBuffer)
            // The output holds the resampled length, not the source frame count.
            let outCapacity = AVAudioFrameCount((Double(frameCount) * Double(Self.sampleRate) / srcRate).rounded(.up)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outCapacity) else {
                throw VADAllocationError.bufferAllocationFailed
            }
            // Feed the source exactly once, then signal end of stream so the converter flushes.
            var fed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                if fed {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                fed = true
                outStatus.pointee = .haveData
                return srcBuffer
            }
            if let e = error { throw e }
            buffer = converted
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
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: false
        ) else { throw VADAllocationError.formatCreationFailed }
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else {
            throw VADAllocationError.bufferAllocationFailed
        }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            channelData.update(from: base, count: samples.count)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
