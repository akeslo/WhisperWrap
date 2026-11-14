import AVFoundation
import XCTest
@testable import WhisperWrap

/// A-SLOP-6: loadAsPCM fed the source to the converter on every input callback and sized
/// the output at the source frame count, so non-16 kHz input came back the wrong length.
final class FluidVADProcessorTests: XCTestCase {
    private var urls: [URL] = []

    override func tearDown() {
        for url in urls { try? FileManager.default.removeItem(at: url) }
        urls = []
        super.tearDown()
    }

    /// Writes a mono Float32 WAV of a 440 Hz tone and returns its URL.
    private func writeWAV(frames: AVAudioFrameCount, sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ww-vad-\(UUID().uuidString).wav")
        urls.append(url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<Int(frames) {
            samples[i] = 0.5 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
        }
        try file.write(from: buffer)
        return url
    }

    func testResamples48kHzInputToTheRight16kHzLength() throws {
        let url = try writeWAV(frames: 4800, sampleRate: 48000)
        let samples = try FluidVADProcessor().loadAsPCM(url: url)
        XCTAssertTrue((1590...1610).contains(samples.count), "got \(samples.count) samples")
    }

    func testReads16kHzInputUnchanged() throws {
        let url = try writeWAV(frames: 1600, sampleRate: 16000)
        let samples = try FluidVADProcessor().loadAsPCM(url: url)
        XCTAssertEqual(samples.count, 1600)
    }
}
