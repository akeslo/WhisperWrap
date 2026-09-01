import SwiftUI
import AVFoundation
import Combine
import ServiceManagement
import Carbon
import CoreAudio
import UserNotifications

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
    @Published var selectedClaudeModel: String = "sonnet" {
        didSet {
            UserDefaults.standard.set(selectedClaudeModel, forKey: "dictationClaudeModel")
        }
    }
    /// The raw, pre-Claude transcription from the most recent dictation.
    @Published var lastRawTranscription: String = ""
    /// The Claude-processed output from the most recent dictation, empty if none was generated.
    @Published var lastProcessedOutput: String = ""

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
    /// Set while `loadAudioDevices()` substitutes an available device for one that is
    /// currently unplugged. Suppresses persistence so a temporarily absent mic does not
    /// permanently overwrite the user's saved choice with whatever happened to be first.
    private var isApplyingDeviceFallback = false

    @Published var selectedAudioDeviceID: String? {
        didSet {
            guard !isApplyingDeviceFallback else { return }
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
    // Identifies the in-flight transcriptionTask run so its `defer` can tell whether it's
    // still the current run before clearing shared state (R2). Without this, a task
    // cancelled by cancelTranscription() still runs its `defer` on the next await/return
    // and unconditionally clears isProcessing/transcriptionTask and hides the HUD — even
    // after a cancel-then-immediately-re-record has already started a new task and set
    // both back to true/non-nil. That orphans the new task: nothing points to it any more,
    // so a later cancelTranscription() has nothing to cancel, and the HUD gets hidden out
    // from under active transcription.
    private var currentTranscriptionID: UUID?
    private var silentMonitor = SilentRecordingMonitor()
    private var silentNotificationPosted = false
    
    override init() {
        self.showHUD = UserDefaults.standard.object(forKey: "showHUD") as? Bool ?? true
        self.autoCopy = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true
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
            self.selectedClaudePromptID = ClaudePrompt.builtinPolish.id
        }
        if let savedModel = UserDefaults.standard.string(forKey: "dictationClaudeModel") {
            self.selectedClaudeModel = savedModel
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
    
    /// UserDefaults keys for the persisted dictation hotkey. Without these a
    /// customized hotkey silently reverted to Option+Space on every relaunch.
    static let hotkeyKeyCodeDefaultsKey = "dictationHotkeyKeyCode"
    static let hotkeyModifiersDefaultsKey = "dictationHotkeyModifiers"

    private func setupHotKey() {
        // Main dictation toggle: Option+Space by default, overridden by any saved hotkey.
        let defaults = UserDefaults.standard
        var keyCode = defaults.object(forKey: Self.hotkeyKeyCodeDefaultsKey) as? Int ?? kVK_Space
        var modifiers = defaults.object(forKey: Self.hotkeyModifiersDefaultsKey) as? Int ?? optionKey
        // Guard against a corrupted persisted value (e.g. written directly via
        // `defaults write` with a negative or out-of-range Int) — fall back to the
        // default hotkey rather than handing HotKeyManager values it can't register (R3).
        if UInt32(exactly: keyCode) == nil || UInt32(exactly: modifiers) == nil {
            LoggerService.shared.debug("Corrupted hotkey defaults (keyCode=\(keyCode), modifiers=\(modifiers)) — resetting to Option+Space")
            keyCode = kVK_Space
            modifiers = optionKey
            defaults.removeObject(forKey: Self.hotkeyKeyCodeDefaultsKey)
            defaults.removeObject(forKey: Self.hotkeyModifiersDefaultsKey)
        }
        registerDictationHotkey(keyCode: keyCode, modifiers: modifiers)
        // Show last transcription + AI output: Option+Shift+V
        hotKeyManager.registerAdditional(id: 2, keyCode: kVK_ANSI_V, modifiers: optionKey | shiftKey) { [weak self] in
            Task { @MainActor in
                self?.openLastResultWindow()
            }
        }
    }

    func openLastResultWindow() {
        LastResultWindowController.shared.show(
            rawTranscription: lastRawTranscription,
            processedOutput: lastProcessedOutput
        )
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
            LoggerService.shared.debug("Failed to get audio devices data size")
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
            LoggerService.shared.debug("Failed to get audio devices")
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

            // Allocate exact bytes CoreAudio will write — AudioBufferList is variable-length
            let bufferListData = UnsafeMutableRawPointer.allocate(
                byteCount: Int(inputBufferListSize),
                alignment: MemoryLayout<AudioBufferList>.alignment
            )
            defer { bufferListData.deallocate() }
            let bufferListPtr = bufferListData.assumingMemoryBound(to: AudioBufferList.self)

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

            // Check all buffers for input channels (not just the first)
            let abl = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            guard abl.contains(where: { $0.mNumberChannels > 0 }) else {
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
                // Skip internal CoreAudio virtual aggregate devices
                guard !deviceName.hasPrefix("CADefaultDeviceAggregate") else { continue }
                devices.append((id: String(deviceID), name: deviceName))
            }
        }

        self.availableAudioDevices = devices

        // Prefer the user's persisted choice whenever that device is present — including
        // when it reappears after being unplugged. Only when it is genuinely unavailable
        // do we fall back to the first device, and that fallback is not persisted.
        let preferredID = UserDefaults.standard.string(forKey: "selectedAudioDeviceID")
        if let preferredID, devices.contains(where: { $0.id == preferredID }) {
            if selectedAudioDeviceID != preferredID {
                applyDeviceFallback(preferredID)
            }
        } else if selectedAudioDeviceID == nil ||
                  !devices.contains(where: { $0.id == selectedAudioDeviceID }) {
            applyDeviceFallback(devices.first?.id)
        }
    }

    /// Changes the in-use device without touching the persisted preference.
    private func applyDeviceFallback(_ deviceID: String?) {
        isApplyingDeviceFallback = true
        selectedAudioDeviceID = deviceID
        isApplyingDeviceFallback = false
    }

    func switchAudioDevice(_ deviceID: String) {
        selectedAudioDeviceID = deviceID
        if isRecording {
            // Applying the switch now would mean restarting AVAudioRecorder over the
            // same file, truncating it and silently discarding everything said before
            // the switch. Keep the current take intact and let the new device take
            // effect on the next recording instead.
            LoggerService.shared.debug("Audio device switch deferred — applies to the next recording, current take left intact")
        } else {
            setDefaultInputDevice(deviceID)
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
            LoggerService.shared.debug("Failed to set default input device: \(status)")
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
        UserDefaults.standard.set(keyCode, forKey: Self.hotkeyKeyCodeDefaultsKey)
        UserDefaults.standard.set(modifiers, forKey: Self.hotkeyModifiersDefaultsKey)
        registerDictationHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    /// Single registration path for the dictation toggle, shared by first-launch
    /// setup and user reconfiguration so the two can't drift apart.
    private func registerDictationHotkey(keyCode: Int, modifiers: Int) {
        hotKeyManager.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if HUDWindowController.shared.isSelectingPrompt {
                    HUDWindowController.shared.skipPromptSelection()
                } else if self.isProcessing {
                    self.cancelTranscription()
                } else {
                    self.toggleRecording()
                }
            }
        }
        objectWillChange.send() // Trigger UI update
    }
    
    private func characterFromKeyCode(_ keyCode: Int) -> String? {
        Self.character(forKeyCode: keyCode)
    }

    /// Maps a Carbon virtual key code to its display character/name for the hotkey UI.
    /// Extracted as a pure static function (no `self`, no Carbon side effects) so it is
    /// testable without instantiating the full view model — mirrors the pure-helper
    /// extraction pattern used by macHermit's `FallbackService` usage-parsing helpers.
    nonisolated static func character(forKeyCode keyCode: Int) -> String? {
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
                LoggerService.shared.debug("Failed to toggle launch at login: \(error)")
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
            LoggerService.shared.debug("Microphone access not granted - cannot record")
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

            // Must live in ContentViewModel.scratchDirectory, not the shared system temp
            // dir directly — cleanupOldTempFiles() only sweeps the former, so a recording
            // left behind by a crash or force-quit here would never get reaped.
            let scratchDir = ContentViewModel.scratchDirectory
            try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
            let url = scratchDir.appendingPathComponent("dictation.wav")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            LoggerService.shared.debug("Recording started — model: \(selectedModel.rawValue), device: \(selectedAudioDeviceID ?? "default")")
            if audioRecorder?.record() == true {
                isRecording = true
                isProcessing = false
                transcribedText = ""
                startMonitoring()

                if showHUD {
                    HUDWindowController.shared.setStatus(.listening)
                    HUDWindowController.shared.setAudioDevices(availableAudioDevices, selectedID: selectedAudioDeviceID)
                    HUDWindowController.shared.closeHandler = { [weak self] in
                        Task { @MainActor in
                            self?.stopRecording()
                        }
                    }
                    HUDWindowController.shared.deviceChangeHandler = { [weak self] deviceID in
                        Task { @MainActor in
                            self?.switchAudioDevice(deviceID)
                        }
                    }
                    HUDWindowController.shared.show()
                }
            } else {
                presentRecordingFailure("Couldn't start recording. Check the selected input device.")
            }

        } catch {
            presentRecordingFailure("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    /// Surface a recording-start failure to the user. Without this the hotkey press
    /// produces no HUD, no alert and no recording — a completely silent failure that
    /// only ever reached the debug log.
    private func presentRecordingFailure(_ message: String) {
        LoggerService.shared.debug("Recording failed: \(message)")
        isRecording = false
        isProcessing = false
        audioLevel = 0
        transcribedText = message

        if showHUD {
            HUDWindowController.shared.setStatus(.showingResults)
            HUDWindowController.shared.updateStreamingText("⚠️ \(message)")
            HUDWindowController.shared.show()
            HUDWindowController.shared.showResultsThenFade(duration: 4.0)
        }
    }
    
    func stopRecording() {
        // A stop can arrive after the take already ended (notification action button,
        // recorder delegate failure). Without this guard the HUD flips back to
        // .transcribing and transcription re-runs against an already-deleted temp file.
        guard isRecording else { return }
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

        guard let url = audioRecorder?.url else {
            // No recorder means there is nothing to transcribe — the HUD was just put
            // into .transcribing above, so clear it or it stays on screen forever.
            isProcessing = false
            if showHUD {
                HUDWindowController.shared.clearStreamingText(animated: false)
                HUDWindowController.shared.hide()
            }
            LoggerService.shared.debug("Stop requested with no active recorder — nothing to transcribe")
            return
        }

        // Save recording if enabled
        if saveRecordings, let saveDir = recordingsSaveDirectory {
            saveRecording(from: url, to: saveDir)
        }

        // Release the recorder now that we own the URL — the temp file is consumed
        // (and deleted) by transcription, so nothing should be able to reuse it.
        audioRecorder = nil

        LoggerService.shared.debug("Recording stopped — starting transcription")
        transcribe(url: url)
    }

    private func saveRecording(from sourceURL: URL, to directory: URL) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let destinationURL = Self.uniqueRecordingURL(baseTimestamp: timestamp, in: directory)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            LoggerService.shared.debug("Recording saved to: \(destinationURL.path)")
        } catch {
            LoggerService.shared.debug("Failed to save recording: \(error.localizedDescription)")
        }
    }

    /// Builds a save-recording filename that won't collide with an existing file from a
    /// prior take in the same second. Pure and static so it's directly testable — the
    /// original code always produced `recording_<timestamp>.wav` and silently lost a take
    /// if `FileManager.copyItem` hit an existing file with that name (A-SLOP-11).
    nonisolated static func uniqueRecordingURL(
        baseTimestamp: String,
        in directory: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        var candidate = directory.appendingPathComponent("recording_\(baseTimestamp).wav")
        var suffix = 2
        while fileExists(candidate) {
            candidate = directory.appendingPathComponent("recording_\(baseTimestamp)_\(suffix).wav")
            suffix += 1
        }
        return candidate
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

    func transcribe(url: URL) {
        guard let contentViewModel = contentViewModel else {
            // stopRecording() already put the HUD into .transcribing; bailing out
            // silently here leaves it on screen forever with isProcessing stuck.
            isProcessing = false
            if showHUD {
                HUDWindowController.shared.clearStreamingText(animated: false)
                HUDWindowController.shared.hide()
            }
            LoggerService.shared.debug("Transcription requested with no ContentViewModel — nothing to transcribe")
            return
        }

        isProcessing = true
        let runID = UUID()
        currentTranscriptionID = runID

        transcriptionTask = Task {
            var didShowClaudeResults = false
            defer {
                // Only the still-current run may clear shared state. A stale run whose
                // task was cancelled and superseded by a newer transcribe() call must not
                // stomp the new run's isProcessing/transcriptionTask/HUD state (R2).
                if self.currentTranscriptionID == runID {
                    self.isProcessing = false
                    self.transcriptionTask = nil
                    if self.showHUD {
                        Task { @MainActor in
                            if didShowClaudeResults {
                                // Show results for 5s then fade out
                                HUDWindowController.shared.showResultsThenFade(duration: 5.0)
                            } else {
                                HUDWindowController.shared.clearStreamingText(animated: false)
                                HUDWindowController.shared.hide()
                            }
                        }
                    }
                }
            }

            do {
                // Show download/load progress in HUD if model not yet ready
                let engine = contentViewModel.transcriptionEngine
                var hudProgressTask: Task<Void, Never>? = nil
                if !engine.isReady && self.showHUD {
                    hudProgressTask = Task { @MainActor in
                        while !Task.isCancelled && !engine.isReady {
                            let progress = engine.downloadProgress
                            if progress > 0 && progress < 1.0 {
                                HUDWindowController.shared.updateStreamingText("Downloading model... \(Int(progress * 100))%")
                            } else {
                                HUDWindowController.shared.updateStreamingText("Loading model...")
                            }
                            try? await Task.sleep(nanoseconds: 200_000_000)
                        }
                        HUDWindowController.shared.clearStreamingText(animated: false)
                    }
                }
                defer { hudProgressTask?.cancel() }

                // VAD: trim silence before transcription
                let vadProcessor = FluidVADProcessor()
                let processedURL = await vadProcessor.trimSilence(audioURL: url) ?? url
                let didTrim = processedURL != url
                defer {
                    if didTrim { try? FileManager.default.removeItem(at: processedURL) }
                }

                LoggerService.shared.debug("Transcribing with model: \(selectedModel.rawValue)\(didTrim ? " (VAD trimmed silence)" : "")")
                var text = try await contentViewModel.transcribeDictation(audioURL: processedURL, model: selectedModel)
                LoggerService.shared.debug("Transcription complete — \(text.split(separator: " ").count) words")

                // Check if cancelled before continuing
                if Task.isCancelled { return }

                let originalTranscription = text

                // Claude processing (if enabled and there's text to process)
                if claudeEnabled,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let claudeService = claudeService,
                   let claudePromptManager = claudePromptManager {

                    // Determine which prompt to use
                    var selectedPromptText: String?
                    let defaultID = selectedClaudePromptID ?? ClaudePrompt.builtinPolish.id

                    if showHUD {
                        // Brief overlay after every transcription — pick a prompt or let the default apply.
                        let result = await HUDWindowController.shared.showPromptSelection(
                            prompts: claudePromptManager.allPrompts,
                            defaultID: defaultID
                        )
                        if Task.isCancelled { return }
                        switch result {
                        case .selected(let prompt):
                            selectedPromptText = prompt.prompt
                        case .custom(let customText):
                            selectedPromptText = customText
                        case .skipped, .cancelled:
                            selectedPromptText = nil
                        }
                    } else if let prompt = claudePromptManager.allPrompts.first(where: { $0.id == defaultID }) {
                        selectedPromptText = prompt.prompt
                    }

                    if let promptText = selectedPromptText {
                        if showHUD {
                            HUDWindowController.shared.setStatus(.processingWithClaude)
                        }

                        let stream = claudeService.process(text: text, prompt: promptText, model: selectedClaudeModel)
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
                            didShowClaudeResults = showHUD && !streamedResult.isEmpty
                        } else if ClaudeService.looksLikeError(trimmed) {
                            claudeService.isConnected = false
                        } else {
                            // Empty stdout with no recognizable error text — e.g. the
                            // `claude` CLI isn't on PATH, so `env claude ...` fails
                            // silently to stdout. Ships the raw transcription unchanged,
                            // but flip isConnected so the UI's Claude-status indicator
                            // reflects that processing did not actually happen (R6).
                            LoggerService.shared.debug("Claude processing produced no output — CLI may be missing or misconfigured")
                            claudeService.isConnected = false
                        }
                    }
                }

                self.transcribedText = text
                self.lastRawTranscription = originalTranscription
                self.lastProcessedOutput = (text != originalTranscription) ? text : ""

                // U4: "No Speech Detected" is an in-app sentinel for the HUD/last-result
                // display, not a transcript — copying it would clobber whatever the user
                // actually had on their clipboard for a take that produced no text.
                if autoCopy && text != ContentViewModel.noSpeechDetectedSentinel {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }

            } catch is CancellationError {
                return
            } catch {
                let msg = error.localizedDescription
                LoggerService.shared.debug("Transcription error: \(msg)")
                self.transcribedText = "Error: \(msg)"
                if self.showHUD {
                    HUDWindowController.shared.setStatus(.showingResults)
                    HUDWindowController.shared.updateStreamingText("Error: \(msg)")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }
    
    
    // MARK: - Audio Metering
    
    private func startMonitoring() {
        silentMonitor.reset()
        silentNotificationPosted = false
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                // Normalize power (typically -160 to 0) to 0.0 - 1.0
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0.0, (power + 160) / 160)
                self.audioLevel = normalized

                // Feed raw dBFS into silent-recording monitor
                if let event = self.silentMonitor.update(micDBFS: Double(power)) {
                    switch event {
                    case .started:
                        if !self.silentNotificationPosted {
                            self.silentNotificationPosted = true
                            self.postSilentMicNotification()
                        }
                    case .recovered:
                        self.silentNotificationPosted = false
                        if Bundle.main.bundleIdentifier != nil {
                            UNUserNotificationCenter.current().removePendingNotificationRequests(
                                withIdentifiers: ["whisperwrap.silent-mic"]
                            )
                            UNUserNotificationCenter.current().removeDeliveredNotifications(
                                withIdentifiers: ["whisperwrap.silent-mic"]
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func stopMonitoring() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }

    private func postSilentMicNotification() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "No audio detected"
        content.body = "Your microphone has been silent for 90 seconds. Check your mic or stop recording."
        content.categoryIdentifier = "WW_SILENT_MIC"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "whisperwrap.silent-mic",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { LoggerService.shared.debug("Silent mic notification error: \(error)") }
        }
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

