import Foundation
import AVFoundation
import Combine
import SwiftUI // For AppStorage

enum TTSEngine: String, CaseIterable {
    case system = "System"
    case elevenLabs = "ElevenLabs"
}

struct ElevenLabsVoice: Codable, Identifiable, Hashable {
    let voice_id: String
    let name: String
    
    var id: String { voice_id }
}

struct ElevenLabsVoicesResponse: Codable {
    let voices: [ElevenLabsVoice]
}

struct ElevenLabsSubscriptionResponse: Codable {
    let character_count: Int
    let character_limit: Int
}

struct ElevenLabsErrorDetail: Codable {
    let status: String?
    let message: String?
}

struct ElevenLabsErrorResponse: Codable {
    let detail: ElevenLabsErrorDetail
}

@MainActor
class TTSViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var text: String = ""
    @Published var isSpeaking: Bool = false
    @Published var isPaused: Bool = false
    @Published var contentSource: String? = nil
    
    // Engine & API Key
    @AppStorage("elevenLabsAPIKey") var apiKey: String = ""
    @Published var selectedEngine: TTSEngine = .system
    
    // System Voice & Rate
    @Published var availableSystemVoices: [AVSpeechSynthesisVoice] = []
    @Published var selectedSystemVoice: AVSpeechSynthesisVoice?
    @Published var speechRate: Float = 0.5
    @Published var volume: Float = 1.0
    
    // ElevenLabs Voice
    @Published var availableElevenLabsVoices: [ElevenLabsVoice] = []
    @Published var selectedElevenLabsVoice: ElevenLabsVoice?
    @Published var isFetchingVoices: Bool = false
    @Published var isDownloadingAudio: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var errorMessage: String? = nil
    
    // ElevenLabs Usage
    @Published var usedCharacterCount: Int = 0
    @Published var characterLimit: Int = 0
    @Published var isFetchingCredits: Bool = false
    @Published var creditsError: String? = nil
    
    // Caching
    @Published var lastAudioData: Data? = nil
    private var lastCacheKey: String? = nil
    
    var creditsDisplayString: String {
        if isFetchingCredits { return "Usage: Loading..." }
        if let error = creditsError { return error }
        if characterLimit > 0 {
            return "Usage: \(usedCharacterCount) / \(characterLimit)"
        }
        return "Usage: -- / --"
    }

    func fetchElevenLabsUserInfo() async {
        guard !apiKey.isEmpty, let url = URL(string: "https://api.elevenlabs.io/v1/user/subscription") else { return }
        
        Task { @MainActor in 
            self.isFetchingCredits = true 
            self.creditsError = nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("ElevenLabs User Info Error: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    Task { @MainActor in
                        self.creditsError = "Credits: N/A (No Permission)"
                        self.isFetchingCredits = false
                    }
                    return
                }
                
                Task { @MainActor in self.isFetchingCredits = false }
                return
            }

            if let response = try? JSONDecoder().decode(ElevenLabsSubscriptionResponse.self, from: data) {
                print("Decoded User Info: \(response.character_count) / \(response.character_limit)")
                Task { @MainActor in
                    self.usedCharacterCount = response.character_count
                    self.characterLimit = response.character_limit
                    self.isFetchingCredits = false
                }
            } else {
                print("Failed to decode ElevenLabsSubscriptionResponse")
                Task { @MainActor in self.isFetchingCredits = false }
            }
        } catch {
            LoggerService.shared.debug("Failed to fetch user subscription info: \(error)")
            Task { @MainActor in self.isFetchingCredits = false }
        }
    }
    
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        loadSystemVoices()
    }
    
    // MARK: - Voice Loading
    
    private func loadSystemVoices() {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let noveltyVoices: Set<String> = [
            "Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", 
            "Deranged", "Good News", "Hysterical", "Junior", "Kathy", "Organ", 
            "Pipe Organ", "Princess", "Ralph", "Trinoids", "Whisper", "Zarvox"
        ]
        var uniqueVoices: [String: AVSpeechSynthesisVoice] = [:]
        for voice in allVoices {
            guard voice.language.starts(with: "en"), !noveltyVoices.contains(voice.name) else { continue }
            if let existing = uniqueVoices[voice.name] {
                if voice.quality == .premium && existing.quality != .premium {
                    uniqueVoices[voice.name] = voice
                } else if voice.quality == .enhanced && existing.quality == .default {
                    uniqueVoices[voice.name] = voice
                }
            } else {
                uniqueVoices[voice.name] = voice
            }
        }
        self.availableSystemVoices = uniqueVoices.values.sorted { $0.name < $1.name }
        
        if let defaultVoice = availableSystemVoices.first(where: { $0.identifier == AVSpeechSynthesisVoice.currentLanguageCode() }) ?? availableSystemVoices.first(where: { $0.language.starts(with: "en-US") }) {
            selectedSystemVoice = defaultVoice
        } else {
            selectedSystemVoice = availableSystemVoices.first
        }
    }
    
    func fetchElevenLabsVoices() {
        guard !apiKey.isEmpty else {
            self.errorMessage = "Please enter an API Key."
            return
        }
        isFetchingVoices = true
        errorMessage = nil
        
        // Fetch User Info (Credits)
        Task {
            await fetchElevenLabsUserInfo()
        }
        
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    self.errorMessage = "ElevenLabs Error (\(httpResponse.statusCode)): \(errorText)"
                    self.isFetchingVoices = false
                    return
                }
                
                let responseObj = try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data)
                self.availableElevenLabsVoices = responseObj.voices.sorted { $0.name < $1.name }
                if self.selectedElevenLabsVoice == nil {
                    self.selectedElevenLabsVoice = self.availableElevenLabsVoices.first
                }
                self.isFetchingVoices = false
            } catch {
                LoggerService.shared.debug("Error fetching ElevenLabs voices: \(error)")
                self.errorMessage = "Failed to fetch voices: \(error.localizedDescription)"
                self.isFetchingVoices = false
            }
        }
    }
    
    // MARK: - Playback Control
    
    func speak() {
        guard !text.isEmpty else { return }
        errorMessage = nil
        
        if isPaused {
            resume()
            return
        }
        
        if isSpeaking { return }
        
        if selectedEngine == .system {
            speakSystem()
        } else {
            speakElevenLabs()
        }
    }
    
    // Called when the volume slider changes in UI
    func updateVolume() {
        audioPlayer?.volume = volume
    }
    
    private func speakSystem() {
        // Caching Check
        let voiceId = selectedSystemVoice?.identifier ?? "default"
        let rateKey = String(format: "%.2f", speechRate)
        let cacheKey = "sys-\(voiceId)-\(rateKey)-\(text)"
        
        if let lastKey = lastCacheKey, lastKey == cacheKey, let cachedData = lastAudioData {
            LoggerService.shared.debug("Playing system audio from cache")
            playAudioData(cachedData)
            return
        }
        
        isDownloadingAudio = true // Reuse this flag for "rendering" state
        downloadProgress = 0.0 // System rendering doesn't give granular progress easily, maybe fake it or stays 0
        
        // Capture values on MainActor before detaching
        let textToRender = text
        let voiceToRender = selectedSystemVoice
        let rateToRender = speechRate
        let cacheKeyToUse = cacheKey
        
        Task.detached(priority: .userInitiated) {
            do {
                let audioData = try await self.renderSystemAudio(text: textToRender, voice: voiceToRender, rate: rateToRender)
                
                await MainActor.run {
                    // Save to Cache
                    self.lastAudioData = audioData
                    self.lastCacheKey = cacheKeyToUse
                    
                    self.playAudioData(audioData)
                    self.isDownloadingAudio = false
                }
            } catch {
                await MainActor.run {
                    LoggerService.shared.debug("Error rendering system audio: \(error)")
                    self.errorMessage = "System TTS Error: \(error.localizedDescription)"
                    self.isDownloadingAudio = false
                }
            }
        }
    }
    
    // Helper to play data and set state
    private func playAudioData(_ data: Data) {
        do {
            self.audioPlayer = try AVAudioPlayer(data: data)
            self.audioPlayer?.delegate = self
            self.audioPlayer?.volume = self.volume
            self.audioPlayer?.play()
            self.isSpeaking = true
            self.isPaused = false
        } catch {
            LoggerService.shared.debug("Failed to play audio data: \(error)")
            self.errorMessage = "Playback Error: \(error.localizedDescription)"
        }
    }

    nonisolated private func renderSystemAudio(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) async throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let renderer = SystemAudioRenderer()
        return try await renderer.render(text: text, voice: voice, rate: rate, to: tempURL)
    }
    
    private func speakElevenLabs() {
        guard !apiKey.isEmpty else {
            self.errorMessage = "Please enter an API Key."
            return
        }
        guard let voiceId = selectedElevenLabsVoice?.voice_id else {
            self.errorMessage = "Please select a voice."
            return
        }
        
        let charLimit = 10_000
        if text.count > charLimit {
            self.errorMessage = "Text too long (\(text.count) chars). Limit is \(charLimit)."
            return
        }
        
        isDownloadingAudio = true
        downloadProgress = 0.0
        
        // Caching Check
        let cacheKey = "\(text)-\(voiceId)"
        if let lastKey = lastCacheKey, lastKey == cacheKey, let cachedData = lastAudioData {
            LoggerService.shared.debug("Playing from cache for key: \(cacheKey)")
            do {
                self.audioPlayer = try AVAudioPlayer(data: cachedData)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.volume = self.volume
                self.audioPlayer?.play()
                self.isDownloadingAudio = false
                self.isSpeaking = true
                self.isPaused = false
                return
            } catch {
                LoggerService.shared.debug("Failed to play cached audio: \(error)")
                // Fallthrough to re-download if cache fails
            }
        }
        
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2", // Updated to newer model
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.5
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    var errorData = Data()
                    for try await byte in bytes { errorData.append(byte) }
                    
                    var displayMessage = "Error (\(httpResponse.statusCode))"
                    
                    if let errorObj = try? JSONDecoder().decode(ElevenLabsErrorResponse.self, from: errorData),
                       let msg = errorObj.detail.message {
                        displayMessage = msg
                    } else {
                         let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown Error"
                         displayMessage = "Error (\(httpResponse.statusCode)): \(errorText)"
                    }
                    
                    LoggerService.shared.debug("ElevenLabs API Error: \(displayMessage)")
                    self.errorMessage = displayMessage
                    
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                         self.creditsError = "Credits: N/A (No Permission)"
                    }
                    
                    self.isDownloadingAudio = false
                    self.downloadProgress = 0.0
                    return
                }
                
                var data = Data()
                let totalBytes = response.expectedContentLength
                var receivedBytes: Int64 = 0
                
                for try await byte in bytes {
                    data.append(byte)
                    receivedBytes += 1
                    
                    if totalBytes > 0 {
                        let progress = Double(receivedBytes) / Double(totalBytes)
                        // Throttle UI updates slightly
                        if abs(progress - self.downloadProgress) > 0.05 || receivedBytes == totalBytes {
                            self.downloadProgress = progress
                        }
                    }
                }
                
                // Save to Cache
                self.lastAudioData = data
                self.lastCacheKey = cacheKey
                
                self.audioPlayer = try AVAudioPlayer(data: data)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.volume = self.volume // Apply volume
                self.audioPlayer?.play()
                self.isDownloadingAudio = false
                self.downloadProgress = 0.0
                self.isSpeaking = true
                self.isPaused = false
            } catch {
                LoggerService.shared.debug("Error playing ElevenLabs audio: \(error)")
                self.errorMessage = "Playback Error: \(error.localizedDescription)"
                self.isDownloadingAudio = false
                self.downloadProgress = 0.0
            }
        }
    }
    
    func saveLastAudio(to url: URL) {
        guard let data = lastAudioData else { return }
        do {
            try data.write(to: url)
            LoggerService.shared.debug("Saved audio to \(url.path)")
        } catch {
            LoggerService.shared.debug("Failed to save audio: \(error)")
            self.errorMessage = "Failed to save file: \(error.localizedDescription)"
        }
    }
    
    func truncateText() {
        let charLimit = 10_000
        if text.count > charLimit {
            text = String(text.prefix(charLimit))
        }
    }
    
    func pause() {
        if let player = audioPlayer, player.isPlaying {
            player.pause()
            isPaused = true
            isSpeaking = false // UI state update
        }
    }
    
    func resume() {
        if let player = audioPlayer, !player.isPlaying {
            player.play()
            isPaused = false
            isSpeaking = true // UI state update
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0 // Reset
        audioPlayer = nil
        
        // Also stop any rendering if possible? 
        // usage not easy to cancel via this simple stop, but playback stops immediately.
        
        isSpeaking = false
        isPaused = false
    }
    
    func loadText(from url: URL) {
        let startAccess = url.startAccessingSecurityScopedResource()
        defer { if startAccess { url.stopAccessingSecurityScopedResource() } }
        
        var content = ""
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Fallback to ASCII/MacOSRoman if UTF-8 fails
            if let c = try? String(contentsOf: url, encoding: .ascii) { content = c }
        }
        
        if content.isEmpty {
            LoggerService.shared.debug("Failed to load text content or empty file.")
            return
        }
        
        LoggerService.shared.debug("Loaded file. Chars: \(content.count)")
        
        var extractedText = ""
        
        if url.pathExtension.lowercased() == "json" {
            if let data = content.data(using: .utf8),
               let jsonArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                 let texts = jsonArray.compactMap { $0["text"] as? String }
                 if !texts.isEmpty { extractedText = texts.joined(separator: " ") }
            }
            
            if extractedText.isEmpty {
                let lines = content.components(separatedBy: .newlines)
                var texts: [String] = []
                for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if let data = line.data(using: .utf8),
                       let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let textVal = jsonObject["text"] as? String {
                        texts.append(textVal)
                    }
                }
                if !texts.isEmpty { extractedText = texts.joined(separator: " ") }
            }
        }
        
        self.text = extractedText.isEmpty ? content : extractedText
        self.contentSource = url.lastPathComponent
    }
    
    // MARK: - Delegates
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
         Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isPaused = false
        }
    }
}

// Helper class to handle AVSpeechSynthesizer delegate callbacks for file rendering
// Moved outside TTSViewModel to avoid nesting issues and isolation conflicts
private class SystemAudioRenderer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?
    private let synthesizer = AVSpeechSynthesizer()
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func render(text: String, voice: AVSpeechSynthesisVoice?, rate: Float, to url: URL) async throws -> Data {
        self.outputURL = url
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let utterance = AVSpeechUtterance(string: text)
            if let voice = voice { utterance.voice = voice }
            utterance.rate = rate
            
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self = self, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                
                do {
                    if self.outputFile == nil {
                        let settings = pcmBuffer.format.settings
                        self.outputFile = try AVAudioFile(forWriting: url, settings: settings)
                    }
                    try self.outputFile?.write(from: pcmBuffer)
                } catch {
                    self.continuation?.resume(throwing: error)
                    self.continuation = nil
                }
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Finished writing
        if let url = outputURL {
            do {
                // Determine format and load data. simple read.
                let data = try Data(contentsOf: url)
                outputFile = nil // Close file
                continuation?.resume(returning: data)
                
                // Cleanup? We return data, so maybe we keep the file or delete it? 
                // The ViewModel saves it to cache. We can delete the temp file.
                try? FileManager.default.removeItem(at: url)
                
            } catch {
                continuation?.resume(throwing: error)
            }
        } else {
            continuation?.resume(throwing: NSError(domain: "SystemAudioRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No output URL"]))
        }
        continuation = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        continuation?.resume(throwing: NSError(domain: "SystemAudioRenderer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Rendering cancelled"]))
        continuation = nil
    }
}
