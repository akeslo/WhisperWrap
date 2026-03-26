import SwiftUI
import AVFoundation
import Combine
import ServiceManagement
import Carbon
import CoreAudio

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
    @Published var saveRecordings: Bool = false {
        didSet {
            UserDefaults.standard.set(saveRecordings, forKey: "saveRecordings")
        }
    }
    @Published var recordingsSaveDirectory: URL? {
        didSet {
            if let url = recordingsSaveDirectory {
                UserDefaults.standard.set(url.path, forKey: "recordingsSaveDirectory")
            } else {
                UserDefaults.standard.removeObject(forKey: "recordingsSaveDirectory")
            }
        }
    }

    // Claude Processing Settings
    @Published var claudeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(claudeEnabled, forKey: "dictationClaudeEnabled")
        }
    }
    @Published var selectedClaudePromptID: UUID? {
        didSet {
            if let id = selectedClaudePromptID {
                UserDefaults.standard.set(id.uuidString, forKey: "dictationClaudePromptID")
            } else {
                UserDefaults.standard.removeObject(forKey: "dictationClaudePromptID")
            }
        }
    }

    enum ActiveAlert: Identifiable {
        case accessibility
        case microphoneDenied

        var id: Int {
            switch self {
            case .accessibility: return 0
            case .microphoneDenied: return 1
            }
        }
    }

    @Published var activeAlert: ActiveAlert?

    // Audio Device Selection
    @Published var availableAudioDevices: [(id: String, name: String)] = []
    @Published var selectedAudioDeviceID: String? {
        didSet {
            if let id = selectedAudioDeviceID {
                UserDefaults.standard.set(id, forKey: "selectedAudioDeviceID")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedAudioDeviceID")
            }
        }
    }

    // Dependencies
    var contentViewModel: ContentViewModel?
    var claudeService: ClaudeService?
    var claudePromptManager: ClaudePromptManager?
    let hotKeyManager = HotKeyManager()

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var meterTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?
    
    override init() {
        self.showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        self.autoCopy = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true
        self.autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? false
        self.saveRecordings = UserDefaults.standard.object(forKey: "saveRecordings") as? Bool ?? false

        if let savedModelRaw = UserDefaults.standard.string(forKey: "selectedModel"),
           let savedModel = Model(rawValue: savedModelRaw) {
            self.selectedModel = savedModel
        }

        // Load saved recordings directory
        if let savedPath = UserDefaults.standard.string(forKey: "recordingsSaveDirectory") {
            self.recordingsSaveDirectory = URL(fileURLWithPath: savedPath)
        }

        // Load Claude settings
        self.claudeEnabled = UserDefaults.standard.bool(forKey: "dictationClaudeEnabled")
        if let savedID = UserDefaults.standard.string(forKey: "dictationClaudePromptID"),
           let uuid = UUID(uuidString: savedID) {
            self.selectedClaudePromptID = uuid
        } else {
            self.selectedClaudePromptID = ClaudePrompt.builtinCleanUp.id
        }

        super.init()

        // Load saved device first, before loading available devices
        if let savedDeviceID = UserDefaults.standard.string(forKey: "selectedAudioDeviceID") {
            self.selectedAudioDeviceID = savedDeviceID
        }

        loadAudioDevices()

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

    // MARK: - Recording Directory Management

    func selectRecordingsDirectory() {
        let hadPreviousDirectory = recordingsSaveDirectory != nil

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to save audio recordings"

        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.recordingsSaveDirectory = url
            } else {
                // User cancelled
                // Only uncheck if this was the initial selection (no previous directory)
                if !hadPreviousDirectory {
                    self?.saveRecordings = false
                }
                // If changing existing directory, do nothing - keep old directory
            }
        }
    }

    // MARK: - Audio Device Management

    func loadAudioDevices() {
        var devices: [(id: String, name: String)] = []

        // Get all audio input devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("Failed to get audio devices data size")
            self.availableAudioDevices = devices
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        let getDevicesStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard getDevicesStatus == noErr else {
            print("Failed to get audio devices")
            self.availableAudioDevices = devices
            return
        }

        // Filter for input devices and get their names
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputChannelsAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputBufferListSize: UInt32 = 0
            let hasInputStatus = AudioObjectGetPropertyDataSize(
                deviceID,
                &inputChannelsAddress,
                0,
                nil,
                &inputBufferListSize
            )

            guard hasInputStatus == noErr, inputBufferListSize > 0 else {
                continue // Skip devices without input
            }

            // Actually read the buffer list to verify input channels exist
            // Allocate memory for the buffer list
            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer {
                bufferListPtr.deallocate()
            }

            var bufferListSize = inputBufferListSize
            let getBufferListStatus = AudioObjectGetPropertyData(
                deviceID,
                &inputChannelsAddress,
                0,
                nil,
                &bufferListSize,
                bufferListPtr
            )

            guard getBufferListStatus == noErr else {
                continue
            }

            // Check if there are actual input channels
            let bufferList = bufferListPtr.pointee
            var hasInputChannels = false

            // Check the first buffer (most devices have just one)
            if bufferList.mNumberBuffers > 0 && bufferList.mBuffers.mNumberChannels > 0 {
                hasInputChannels = true
            }

            guard hasInputChannels else {
                continue // Skip devices without actual input channels
            }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var nameSize = UInt32(MemoryLayout<CFString?>.size)
            var nameRef: CFString?

            let nameStatus = withUnsafeMutablePointer(to: &nameRef) { pointer in
                AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    pointer
                )
            }

            if nameStatus == noErr, let name = nameRef {
                let deviceName = name as String
                devices.append((id: String(deviceID), name: deviceName))
            }
        }

        self.availableAudioDevices = devices

        // If no device is selected or saved device doesn't exist, default to first available device
        if selectedAudioDeviceID == nil ||
           !devices.contains(where: { $0.id == selectedAudioDeviceID }) {
            selectedAudioDeviceID = devices.first?.id
        }
    }

    private func setDefaultInputDevice(_ deviceIDString: String) {
        guard let deviceID = AudioDeviceID(deviceIDString) else {
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDCopy = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceIDCopy
        )

        if status != noErr {
            print("Failed to set default input device: \(status)")
        }
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
        // Check permissions before recording
        PermissionsManager.shared.checkPermissions()

        // Check if microphone permission is granted
        if !PermissionsManager.shared.hasMicrophoneAccess {
            print("Microphone access not granted - cannot record")
            activeAlert = .microphoneDenied
            return
        }

        // Set the selected audio input device
        if let deviceID = selectedAudioDeviceID {
            setDefaultInputDevice(deviceID)
        }

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
            HUDWindowController.shared.closeHandler = { [weak self] in
                Task { @MainActor in
                    self?.cancelTranscription()
                }
            }
            // Do NOT hide here, wait for transcription
        }

        guard let url = audioRecorder?.url else { return }

        // Save recording if enabled
        if saveRecordings, let saveDir = recordingsSaveDirectory {
            saveRecording(from: url, to: saveDir)
        }

        transcribe(url: url)
    }

    private func saveRecording(from sourceURL: URL, to directory: URL) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "recording_\(timestamp).m4a"
        let destinationURL = directory.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            print("Recording saved to: \(destinationURL.path)")
        } catch {
            print("Failed to save recording: \(error.localizedDescription)")
        }
    }
    
    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        isRecording = false
        stopMonitoring()
        audioLevel = 0
    }
    
    func cancelTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        isProcessing = false
        if showHUD {
            HUDWindowController.shared.hide()
        }
    }

    private func transcribe(url: URL) {
        guard let contentViewModel = contentViewModel else { return }

        isProcessing = true

        transcriptionTask = Task {
            defer {
                self.isProcessing = false
                self.transcriptionTask = nil
                if self.showHUD {
                    Task { @MainActor in
                        HUDWindowController.shared.hide()
                        HUDWindowController.shared.clearStreamingText()
                    }
                }
            }

            do {
                var text = try await contentViewModel.transcribeDictation(audioURL: url, model: selectedModel)

                // Check if cancelled before continuing
                if Task.isCancelled { return }

                // Claude processing (if enabled)
                if claudeEnabled,
                   let claudeService = claudeService,
                   let claudePromptManager = claudePromptManager,
                   let promptID = selectedClaudePromptID,
                   let prompt = claudePromptManager.allPrompts.first(where: { $0.id == promptID }) {

                    if showHUD {
                        HUDWindowController.shared.setStatus(.processingWithClaude)
                    }

                    let stream = claudeService.process(text: text, prompt: prompt.prompt)
                    var streamedResult = ""
                    for await chunk in stream {
                        if Task.isCancelled { return }
                        streamedResult += chunk
                        if showHUD {
                            HUDWindowController.shared.updateStreamingText(streamedResult)
                        }
                    }

                    let trimmed = streamedResult.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !ClaudeService.looksLikeError(trimmed) {
                        text = trimmed
                    } else if ClaudeService.looksLikeError(trimmed) {
                        claudeService.isConnected = false
                    }
                }

                self.transcribedText = text

                if autoCopy || autoPaste {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }

                if autoPaste {
                    injectText()
                }

            } catch is CancellationError {
                // Silently handle cancellation
                return
            } catch {
                self.transcribedText = "Error: \(error.localizedDescription)"
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

        // Check if accessibility permissions are granted before attempting paste
        if !AXIsProcessTrusted() {
            print("⚠️ Accessibility permissions not granted - cannot auto-paste")
            print("📋 Text has been copied to clipboard")

            // Ensure we're on main thread and app is active to show alert
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.activeAlert = .accessibility
            }
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

