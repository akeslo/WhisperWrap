import SwiftUI
import AVFoundation
import Combine
import ServiceManagement
import Carbon

@MainActor
class DictationViewModel: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var transcribedText = ""
    @Published var audioLevel: Float = 0.0
    @Published var launchAtLogin: Bool = false {
        didSet {
            if launchAtLogin != oldValue {
                toggleLaunchAtLogin(enabled: launchAtLogin)
            }
        }
    }
    
    // Feature Settings
    @Published var selectedModel: Model = .base {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }
    @Published var autoCopy: Bool = true {
        didSet {
            UserDefaults.standard.set(autoCopy, forKey: "autoCopy")
        }
    }
    @Published var autoPaste: Bool = false {
        didSet {
            UserDefaults.standard.set(autoPaste, forKey: "autoPaste")
        }
    }
    @Published var showHUD: Bool {
        didSet {
            UserDefaults.standard.set(showHUD, forKey: "showHUD")
        }
    }
    
    // Dependencies
    var contentViewModel: ContentViewModel?
    let hotKeyManager = HotKeyManager()
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var meterTimer: Timer?
    
    override init() {
        self.showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        self.autoCopy = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true
        self.autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? false
        
        if let savedModelRaw = UserDefaults.standard.string(forKey: "selectedModel"),
           let savedModel = Model(rawValue: savedModelRaw) {
            self.selectedModel = savedModel
        }
        
        super.init()
        checkLaunchAtLogin()
        setupHotKey()
    }
    
    private func setupHotKey() {
        hotKeyManager.eventHandler = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        // Register default hotkey: Option+Space
        hotKeyManager.register(keyCode: kVK_Space, modifiers: optionKey)
    }
    
    // MARK: - Hotkey Configuration
    var hotkeyDisplayString: String {
        var parts: [String] = []
        
        if hotKeyManager.modifiers & cmdKey != 0 { parts.append("⌘") }
        if hotKeyManager.modifiers & shiftKey != 0 { parts.append("⇧") }
        if hotKeyManager.modifiers & optionKey != 0 { parts.append("⌥") }
        if hotKeyManager.modifiers & controlKey != 0 { parts.append("⌃") }
        
        // Convert key code to character
        if let char = characterFromKeyCode(hotKeyManager.key) {
            parts.append(char.uppercased())
        }
        
        return parts.joined()
    }
    
    func setHotkey(keyCode: Int, modifiers: Int) {
        hotKeyManager.register(keyCode: keyCode, modifiers: modifiers)
        objectWillChange.send() // Trigger UI update
    }
    
    private func characterFromKeyCode(_ keyCode: Int) -> String? {
        let keyMap: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space",
        ]
        return keyMap[keyCode]
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            // Bring app to front if it's in background UNLESS HUD is on?
            // User requested HUD similar to "this" (screenshot implied floating).
            // If main app is closed, HUD is useful.
            
            if !showHUD {
                 NSApp.activate(ignoringOtherApps: true)
            }
            startRecording()
        }
    }
    
    private func checkLaunchAtLogin() {
        // Simple check for SMAppService functionality
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled { return }
                    try SMAppService.mainApp.register()
                } else {
                    if SMAppService.mainApp.status == .notFound { return }
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to toggle launch at login: \(error)")
                // Revert if failed
                DispatchQueue.main.async {
                    self.launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        }
    }
    
    func startRecording() {
        // let audioSession = AVAudioSession.sharedInstance() // permission check
        // _ = AVAudioSession.sharedInstance()
        
        do {
            // try audioSession.setCategory(.playAndRecord, mode: .default)
            // try audioSession.setActive(true) // Unnecessary/Unavailable on macOS
            
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation.m4a")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            if audioRecorder?.record() == true {
                isRecording = true
                isProcessing = false
                transcribedText = ""
                startMonitoring()
                
                if showHUD {
                    HUDWindowController.shared.setStatus(.listening)
                    HUDWindowController.shared.closeHandler = { [weak self] in
                        Task { @MainActor in
                            self?.stopRecording()
                        }
                    }
                    HUDWindowController.shared.show()
                }
            } else {
                print("Failed to start recording")
            }
            
        } catch {
            print("Error setting up recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        stopMonitoring()
        
        if showHUD {
            HUDWindowController.shared.setStatus(.transcribing)
            HUDWindowController.shared.updateAudioLevel(0) // Reset 0 for calm wave
            // Do NOT hide here, wait for transcription
        }
        
        guard let url = audioRecorder?.url else { return }
        transcribe(url: url)
    }
    
    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        isRecording = false
        stopMonitoring()
        audioLevel = 0
    }
    
    private func transcribe(url: URL) {
        guard let contentViewModel = contentViewModel else { return }
        
        isProcessing = true
        
        Task {
            do {
                let text = try await contentViewModel.transcribeDictation(audioURL: url, model: selectedModel)
                self.transcribedText = text
                
                if autoCopy || autoPaste {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                
                if autoPaste {
                    injectText()
                }
                
            } catch {
                self.transcribedText = "Error: \(error.localizedDescription)"
            }
            self.isProcessing = false
            
            await MainActor.run {
                if self.showHUD {
                    HUDWindowController.shared.hide()
                }
            }
        }
    }
    
    private func injectText() {
        // Check if the main UI window is actually open
        let isMainInterfaceVisible = NSApp.windows.contains { 
            $0.isVisible && !$0.isKind(of: NSPanel.self) 
        }

        // If the UI is open and focused (active), do NOT auto-paste or minimize.
        // Just let the transcription appear in the app UI.
        if NSApp.isActive && isMainInterfaceVisible {
            return
        }
    
        // If UI is not active (e.g. background/minimized) OR only the HUD was visible,
        // we want to paste into the previously focused app.
        // Original behavior: Hide app to ensure focus switch, then paste.
        NSApp.hide(nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .hidSystemState)
            
            let vKeyCode = CGKeyCode(kVK_ANSI_V)
            
            // Cmd + V down
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            
            // Cmd + V up
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Audio Metering
    
    private func startMonitoring() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                // Normalize power (typically -160 to 0) to 0.0 - 1.0
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0.0, (power + 160) / 160)
                self.audioLevel = normalized
            }
        }
    }
    
    private func stopMonitoring() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.stopRecording()
            }
        }
    }
}

