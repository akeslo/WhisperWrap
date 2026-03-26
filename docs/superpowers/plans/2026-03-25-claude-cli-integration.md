# Claude CLI Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional Claude CLI processing to WhisperWrap's transcription pipeline, letting users pipe speech-to-text output through Claude for cleanup, summarization, or custom processing.

**Architecture:** New `ClaudeService` wraps the `claude` CLI via existing `ShellService.streamCommand()`. Prompt management uses `UserDefaults` with 3 built-in presets + user-saved custom prompts. Both dictation and file transcription flows get an always-on toggle that, when enabled, streams transcription text through Claude before final output.

**Tech Stack:** Swift/SwiftUI, ShellService (Process/Pipe), UserDefaults/AppStorage, AsyncStream

---

### Task 1: ClaudeService — CLI Detection and Authentication

**Files:**
- Create: `Sources/WhisperWrap/ClaudeService.swift`

- [ ] **Step 1: Create ClaudeService with availability check**

Create `Sources/WhisperWrap/ClaudeService.swift`:

```swift
import Foundation

@MainActor
class ClaudeService: ObservableObject {
    @Published var isConnected: Bool {
        didSet {
            UserDefaults.standard.set(isConnected, forKey: "claudeConnected")
        }
    }
    @Published var claudePath: String?
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?

    private let shell = ShellService()

    init() {
        self.isConnected = UserDefaults.standard.bool(forKey: "claudeConnected")
    }

    /// Check if claude CLI is installed and return its path
    func checkAvailability() async -> String? {
        do {
            let result = try await shell.runCommand("which claude")
            let path = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                claudePath = path
                return path
            }
        } catch {
            // claude not found in PATH
        }
        claudePath = nil
        return nil
    }

    /// Verify that claude CLI is authenticated by running a trivial command
    func verifyAuth() async -> Bool {
        do {
            let result = try await shell.runCommand("claude --print \"hello\" 2>&1")
            let output = result.trimmingCharacters(in: .whitespacesAndNewlines)
            // If it returns text without error, auth is good
            if !output.lowercased().contains("error") && !output.lowercased().contains("login") && !output.isEmpty {
                isConnected = true
                return true
            }
        } catch {
            // Auth failed
        }
        isConnected = false
        return false
    }

    /// Process text through Claude CLI, streaming output line by line
    func process(text: String, prompt: String) -> AsyncStream<String> {
        // Escape text for shell: use a temp file to avoid quoting issues
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("claude_input_\(UUID().uuidString).txt")
        let fullPrompt = "\(prompt)\n\n---\n\n\(text)"
        try? fullPrompt.write(to: tempFile, atomically: true, encoding: .utf8)

        let command = "cat \"\(tempFile.path)\" | claude --print 2>&1; rm -f \"\(tempFile.path)\""
        return shell.streamCommand(command)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -5`
Expected: Build succeeds (or only pre-existing warnings)

- [ ] **Step 3: Commit**

```bash
git add Sources/WhisperWrap/ClaudeService.swift
git commit -m "feat: add ClaudeService with CLI detection and streaming"
```

---

### Task 2: Prompt Management Model

**Files:**
- Create: `Sources/WhisperWrap/ClaudePrompt.swift`

- [ ] **Step 1: Create the ClaudePrompt model and defaults**

Create `Sources/WhisperWrap/ClaudePrompt.swift`:

```swift
import Foundation

struct ClaudePrompt: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var isBuiltin: Bool

    init(id: UUID = UUID(), name: String, prompt: String, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isBuiltin = isBuiltin
    }

    static let builtinCleanUp = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Clean Up",
        prompt: "Fix grammar, punctuation, and remove filler words. Keep the original meaning intact. Return only the cleaned text.",
        isBuiltin: true
    )

    static let builtinSummarize = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Summarize",
        prompt: "Condense this into key points. Be concise.",
        isBuiltin: true
    )

    static let builtinActionItems = ClaudePrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Action Items",
        prompt: "Extract action items and to-dos as a bulleted list.",
        isBuiltin: true
    )

    static let builtins: [ClaudePrompt] = [builtinCleanUp, builtinSummarize, builtinActionItems]
}

@MainActor
class ClaudePromptManager: ObservableObject {
    @Published var prompts: [ClaudePrompt] = []

    private let storageKey = "claudeCustomPrompts"

    init() {
        loadPrompts()
    }

    var allPrompts: [ClaudePrompt] {
        ClaudePrompt.builtins + prompts
    }

    func saveCustomPrompt(name: String, prompt: String) {
        let newPrompt = ClaudePrompt(name: name, prompt: prompt)
        prompts.append(newPrompt)
        persist()
    }

    func deleteCustomPrompt(_ prompt: ClaudePrompt) {
        guard !prompt.isBuiltin else { return }
        prompts.removeAll { $0.id == prompt.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadPrompts() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClaudePrompt].self, from: data) else {
            return
        }
        prompts = decoded
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/WhisperWrap/ClaudePrompt.swift
git commit -m "feat: add ClaudePrompt model with builtins and custom prompt storage"
```

---

### Task 3: HUD — Add processingWithClaude State with Streaming Text

**Files:**
- Modify: `Sources/WhisperWrap/HUDState.swift`
- Modify: `Sources/WhisperWrap/HUDView.swift`
- Modify: `Sources/WhisperWrap/HUDWindowController.swift`

- [ ] **Step 1: Add new HUD status and streaming text property**

In `Sources/WhisperWrap/HUDState.swift`, replace the `HUDStatus` enum and add a streaming text property:

```swift
// Old:
    enum HUDStatus {
        case listening
        case transcribing
    }

    @Published var audioLevel: Float = 0.0

// New:
    enum HUDStatus {
        case listening
        case transcribing
        case processingWithClaude
    }

    @Published var audioLevel: Float = 0.0
    @Published var streamingText: String = ""
```

- [ ] **Step 2: Update HUDView to show streaming text for the Claude state**

In `Sources/WhisperWrap/HUDView.swift`, replace the entire `body` with a version that handles the new state. The HUD needs to expand when showing streaming text:

```swift
import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: hudIcon)
                    .font(.title2)
                    .foregroundColor(hudIconColor)
                    .symbolEffect(.pulse, isActive: state.status == .listening)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WhisperWrap")
                        .font(.headline)
                        .fixedSize()
                    Text(hudStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }

                Spacer()

                if state.status != .processingWithClaude {
                    // Visualizer - organic "dancing" bars
                    HStack(spacing: 4) {
                        ForEach(0..<20) { index in
                            let t = state.phase
                            let i = Double(index)
                            let h1 = sin(t + i * 0.6)
                            let h2 = cos(t * 0.8 - i * 1.2)
                            let h3 = sin(t * 0.2 + i * 2.5)
                            let baseSignal = abs(h1 + h2 + 0.5 * h3)
                            let wave = CGFloat(baseSignal) * 12.0

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.blue)
                                .frame(width: 4, height: 4 + wave * (0.5 + CGFloat(state.audioLevel) * 5.0) + (CGFloat(state.audioLevel) * 30))
                        }
                    }
                    .frame(height: 40)
                    .animation(.linear(duration: 0.05), value: state.phase)
                }

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(state.status == .listening ? "Stop Recording" : "Cancel")
            }
            .padding()

            if state.status == .processingWithClaude && !state.streamingText.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(state.streamingText)
                            .font(.system(.body, design: .default))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                            .id("streamBottom")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: state.streamingText) { _, _ in
                        withAnimation {
                            proxy.scrollTo("streamBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(10)
    }

    private var hudIcon: String {
        switch state.status {
        case .listening: return "mic.fill"
        case .transcribing: return "waveform.circle.fill"
        case .processingWithClaude: return "brain"
        }
    }

    private var hudIconColor: Color {
        switch state.status {
        case .listening: return .red
        case .transcribing: return .orange
        case .processingWithClaude: return .purple
        }
    }

    private var hudStatusText: String {
        switch state.status {
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processingWithClaude: return "Processing with Claude..."
        }
    }
}
```

- [ ] **Step 3: Update HUDWindowController to support dynamic sizing for streaming text**

In `Sources/WhisperWrap/HUDWindowController.swift`, add a method to update streaming text and resize the panel:

```swift
// Add after the existing setStatus method:
    func updateStreamingText(_ text: String) {
        hudState.streamingText = text
        // Resize window to fit content when streaming
        if let panel = window {
            let hasText = !text.isEmpty
            let newHeight: CGFloat = hasText ? 280 : 80
            let newWidth: CGFloat = hasText ? 500 : 450
            var frame = panel.frame
            let heightDiff = newHeight - frame.height
            frame.size.height = newHeight
            frame.size.width = newWidth
            frame.origin.y -= heightDiff // Grow upward
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    func clearStreamingText() {
        hudState.streamingText = ""
        // Reset window size
        if let panel = window {
            var frame = panel.frame
            let heightDiff = 80 - frame.height
            frame.size.height = 80
            frame.size.width = 450
            frame.origin.y -= heightDiff
            panel.setFrame(frame, display: true, animate: true)
        }
    }
```

- [ ] **Step 4: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperWrap/HUDState.swift Sources/WhisperWrap/HUDView.swift Sources/WhisperWrap/HUDWindowController.swift
git commit -m "feat: add processingWithClaude HUD state with streaming text display"
```

---

### Task 4: Dictation Settings UI — Claude Processing Section

**Files:**
- Modify: `Sources/WhisperWrap/DictationViewModel.swift`
- Modify: `Sources/WhisperWrap/DictationSettingsView.swift`

- [ ] **Step 1: Add Claude settings properties to DictationViewModel**

In `Sources/WhisperWrap/DictationViewModel.swift`, add these published properties after the existing `saveRecordings` / `recordingsSaveDirectory` block (around line 56):

```swift
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
```

In the `override init()` method, after loading `saveRecordings` (around line 106), add:

```swift
        self.claudeEnabled = UserDefaults.standard.bool(forKey: "dictationClaudeEnabled")
        if let savedID = UserDefaults.standard.string(forKey: "dictationClaudePromptID"),
           let uuid = UUID(uuidString: savedID) {
            self.selectedClaudePromptID = uuid
        } else {
            self.selectedClaudePromptID = ClaudePrompt.builtinCleanUp.id
        }
```

Also add a reference to `ClaudeService` alongside the existing `contentViewModel` dependency (around line 84):

```swift
    var claudeService: ClaudeService?
    var claudePromptManager: ClaudePromptManager?
```

- [ ] **Step 2: Add Claude Processing section to DictationSettingsView**

In `Sources/WhisperWrap/DictationSettingsView.swift`, add `claudeService` and `claudePromptManager` as observed objects, and add a new section after the hotkey section. Replace the entire struct:

```swift
import SwiftUI
import Carbon

struct DictationSettingsView: View {
    @ObservedObject var viewModel: DictationViewModel
    @ObservedObject var claudeService: ClaudeService
    @ObservedObject var claudePromptManager: ClaudePromptManager
    @State private var customPromptName: String = ""
    @State private var customPromptText: String = ""
    @State private var showingSetupError: Bool = false
    @State private var setupErrorMessage: String = ""

    var body: some View {
        GroupBox(label: Label("Settings", systemImage: "gear")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $viewModel.selectedModel) {
                        ForEach(Model.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)

                    Spacer()

                    Toggle("Start at Login", isOn: $viewModel.launchAtLogin)
                        .toggleStyle(.switch)
                }

                HStack {
                    Text("Input Device")
                        .frame(width: 100, alignment: .leading)
                    Picker("", selection: $viewModel.selectedAudioDeviceID) {
                        ForEach(viewModel.availableAudioDevices, id: \.id) { device in
                            Text(device.name).tag(device.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)

                    Spacer()
                }

                Divider()

                HStack {
                    Toggle("Auto Copy", isOn: $viewModel.autoCopy)
                    Toggle("Auto Paste", isOn: $viewModel.autoPaste)
                        .help("Requires Accessibility Permissions")
                    Toggle("Show HUD", isOn: $viewModel.showHUD)
                    Toggle("Save Recordings", isOn: Binding(
                        get: { viewModel.saveRecordings },
                        set: { newValue in
                            if newValue && viewModel.recordingsSaveDirectory == nil {
                                viewModel.saveRecordings = true
                                viewModel.selectRecordingsDirectory()
                            } else {
                                viewModel.saveRecordings = newValue
                            }
                        }
                    ))
                }

                // Show save path if recordings are being saved
                if viewModel.saveRecordings, let saveDir = viewModel.recordingsSaveDirectory {
                    HStack(spacing: 8) {
                        Text("Save Path:")
                            .foregroundColor(.secondary)
                        Text(saveDir.path)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change...") {
                            viewModel.selectRecordingsDirectory()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                HStack {
                    Text("Global Hotkey:")
                    Spacer()
                    HotkeyRecorderView(viewModel: viewModel)
                }
            }
            .padding(8)
        }
        .padding(.horizontal)

        // MARK: - Claude Processing Section
        GroupBox(label: Label("Claude Processing", systemImage: "brain")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle("Process with Claude", isOn: Binding(
                        get: { viewModel.claudeEnabled },
                        set: { newValue in
                            if newValue {
                                enableClaude()
                            } else {
                                viewModel.claudeEnabled = false
                            }
                        }
                    ))
                    .toggleStyle(.switch)

                    Spacer()

                    if claudeService.isConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if claudeService.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.claudeEnabled {
                    HStack {
                        Text("Prompt")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $viewModel.selectedClaudePromptID) {
                            ForEach(claudePromptManager.allPrompts) { prompt in
                                Text(prompt.name).tag(prompt.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)

                        Spacer()

                        // Delete button for custom prompts
                        if let selectedID = viewModel.selectedClaudePromptID,
                           let selected = claudePromptManager.allPrompts.first(where: { $0.id == selectedID }),
                           !selected.isBuiltin {
                            Button(action: {
                                claudePromptManager.deleteCustomPrompt(selected)
                                viewModel.selectedClaudePromptID = ClaudePrompt.builtinCleanUp.id
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Delete this custom prompt")
                        }
                    }

                    Divider()

                    // Custom prompt creation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Save Custom Prompt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("Name", text: $customPromptName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                            TextField("Prompt instruction...", text: $customPromptText)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                guard !customPromptName.isEmpty, !customPromptText.isEmpty else { return }
                                claudePromptManager.saveCustomPrompt(name: customPromptName, prompt: customPromptText)
                                // Select the newly saved prompt
                                if let newPrompt = claudePromptManager.prompts.last {
                                    viewModel.selectedClaudePromptID = newPrompt.id
                                }
                                customPromptName = ""
                                customPromptText = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(customPromptName.isEmpty || customPromptText.isEmpty)
                        }
                    }
                }
            }
            .padding(8)
        }
        .padding(.horizontal)
        .alert("Claude Setup", isPresented: $showingSetupError) {
            Button("OK") { }
        } message: {
            Text(setupErrorMessage)
        }
    }

    private func enableClaude() {
        Task {
            // Check if claude CLI is available
            guard let _ = await claudeService.checkAvailability() else {
                setupErrorMessage = "Claude CLI not found. Install it from https://claude.ai/download and make sure 'claude' is in your PATH."
                showingSetupError = true
                return
            }

            // Verify authentication
            let authed = await claudeService.verifyAuth()
            if authed {
                viewModel.claudeEnabled = true
            } else {
                setupErrorMessage = "Claude CLI is installed but not authenticated. Run 'claude' in your terminal to log in, then try again."
                showingSetupError = true
            }
        }
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -5`

This will fail because `DictationSettingsView` now requires `claudeService` and `claudePromptManager` parameters at its call sites. We'll fix that in Task 6. For now, note the expected errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/WhisperWrap/DictationViewModel.swift Sources/WhisperWrap/DictationSettingsView.swift
git commit -m "feat: add Claude processing settings to dictation UI"
```

---

### Task 5: File Transcription — Claude Processing Controls

**Files:**
- Modify: `Sources/WhisperWrap/TranscriptionView.swift`
- Modify: `Sources/WhisperWrap/ContentViewModel.swift`

- [ ] **Step 1: Add Claude processing properties to ContentViewModel**

In `Sources/WhisperWrap/ContentViewModel.swift`, add these properties after the existing `@Published` block (around line 19):

```swift
    // Claude Processing Settings (file transcription)
    @Published var fileClaudeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(fileClaudeEnabled, forKey: "fileClaudeEnabled")
        }
    }
    @Published var fileClaudePromptID: UUID? {
        didSet {
            if let id = fileClaudePromptID {
                UserDefaults.standard.set(id.uuidString, forKey: "fileClaudePromptID")
            } else {
                UserDefaults.standard.removeObject(forKey: "fileClaudePromptID")
            }
        }
    }
    @Published var claudeStreamingOutput: String = ""
```

In the `init()` method, after `cleanupOldTempFiles()`, add:

```swift
        self.fileClaudeEnabled = UserDefaults.standard.bool(forKey: "fileClaudeEnabled")
        if let savedID = UserDefaults.standard.string(forKey: "fileClaudePromptID"),
           let uuid = UUID(uuidString: savedID) {
            self.fileClaudePromptID = uuid
        } else {
            self.fileClaudePromptID = ClaudePrompt.builtinCleanUp.id
        }
```

Also add service references after `shellService`:

```swift
    var claudeService: ClaudeService?
    var claudePromptManager: ClaudePromptManager?
```

- [ ] **Step 2: Add Claude processing to the file transcription pipeline**

In `Sources/WhisperWrap/ContentViewModel.swift`, add a method after `transcribeDictation`:

```swift
    func processWithClaude(text: String, promptID: UUID?) async -> String {
        guard let claudeService = claudeService,
              let promptManager = claudePromptManager,
              let promptID = promptID,
              let prompt = promptManager.allPrompts.first(where: { $0.id == promptID }) else {
            return text
        }

        var result = ""
        let stream = claudeService.process(text: text, prompt: prompt.prompt)
        for await chunk in stream {
            result += chunk
            claudeStreamingOutput = result
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

In the `processAudio` method, after the line `let outputURL = try await runWhisper(...)` (around line 151), and before `processingStage = "Saving transcription..."`, add Claude processing:

```swift
                // Claude processing for file transcription
                if fileClaudeEnabled, let promptID = fileClaudePromptID {
                    processingStage = "Processing with Claude..."
                    processingProgress = 0.85
                    consoleOutput += "\n🧠 Processing with Claude...\n"
                    claudeStreamingOutput = ""

                    // Read the transcription text
                    let rawText = try String(contentsOf: outputURL, encoding: .utf8)
                    let processedText = await processWithClaude(text: rawText, promptID: promptID)

                    // Overwrite the output file with processed text
                    try processedText.write(to: outputURL, atomically: true, encoding: .utf8)
                    consoleOutput += "✅ Claude processing complete\n"
                }
```

- [ ] **Step 3: Add Claude controls to TranscriptionView**

In `Sources/WhisperWrap/TranscriptionView.swift`, add these parameters and properties to the struct. The view needs access to Claude state. Add after the existing properties at the top of the struct:

```swift
    @ObservedObject var claudeService: ClaudeService
    @ObservedObject var claudePromptManager: ClaudePromptManager
    @Binding var fileClaudeEnabled: Bool
    @Binding var fileClaudePromptID: UUID?
    @State private var showingClaudeSetupError: Bool = false
    @State private var claudeSetupErrorMessage: String = ""
```

In the body, add a Claude section after the Header & Controls `HStack` (after line 54, before the Drop Zone `ZStack`):

```swift
            // MARK: - Claude Processing
            HStack(spacing: 15) {
                Toggle("Process with Claude", isOn: Binding(
                    get: { fileClaudeEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                guard let _ = await claudeService.checkAvailability() else {
                                    claudeSetupErrorMessage = "Claude CLI not found. Install it from https://claude.ai/download and make sure 'claude' is in your PATH."
                                    showingClaudeSetupError = true
                                    return
                                }
                                let authed = await claudeService.verifyAuth()
                                if authed {
                                    fileClaudeEnabled = true
                                } else {
                                    claudeSetupErrorMessage = "Claude CLI is installed but not authenticated. Run 'claude' in your terminal to log in, then try again."
                                    showingClaudeSetupError = true
                                }
                            }
                        } else {
                            fileClaudeEnabled = false
                        }
                    }
                ))
                .toggleStyle(.switch)

                if fileClaudeEnabled {
                    Picker("", selection: $fileClaudePromptID) {
                        ForEach(claudePromptManager.allPrompts) { prompt in
                            Text(prompt.name).tag(prompt.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                Spacer()
            }
            .disabled(isProcessing)
            .alert("Claude Setup", isPresented: $showingClaudeSetupError) {
                Button("OK") { }
            } message: {
                Text(claudeSetupErrorMessage)
            }
```

- [ ] **Step 4: Commit**

```bash
git add Sources/WhisperWrap/TranscriptionView.swift Sources/WhisperWrap/ContentViewModel.swift
git commit -m "feat: add Claude processing to file transcription flow"
```

---

### Task 6: Wire Everything Together — App Entry Point and View Hierarchy

**Files:**
- Modify: `Sources/WhisperWrap/WhisperWrap.swift` (or wherever ContentView is instantiated)
- Modify: `Sources/WhisperWrap/ContentView.swift`

- [ ] **Step 1: Find and read the app entry point and ContentView**

Read `Sources/WhisperWrap/WhisperWrap.swift` and `Sources/WhisperWrap/ContentView.swift` to understand how ViewModels are created and passed to views.

- [ ] **Step 2: Create shared ClaudeService and ClaudePromptManager instances**

These should be created at the app level (in the AppDelegate or wherever `ContentViewModel` and `DictationViewModel` are created) and injected into both ViewModels and views.

In the app delegate / main app struct, create the shared instances:

```swift
let claudeService = ClaudeService()
let claudePromptManager = ClaudePromptManager()
```

Wire them into the ViewModels:

```swift
dictationViewModel.claudeService = claudeService
dictationViewModel.claudePromptManager = claudePromptManager
contentViewModel.claudeService = claudeService
contentViewModel.claudePromptManager = claudePromptManager
```

- [ ] **Step 3: Update all call sites for DictationSettingsView**

Every place `DictationSettingsView(viewModel:)` is used, update to:

```swift
DictationSettingsView(viewModel: dictationViewModel, claudeService: claudeService, claudePromptManager: claudePromptManager)
```

- [ ] **Step 4: Update all call sites for TranscriptionView**

Every place `TranscriptionView(...)` is used, add the new parameters:

```swift
TranscriptionView(
    consoleOutput: $contentViewModel.consoleOutput,
    isProcessing: $contentViewModel.isProcessing,
    processingStage: $contentViewModel.processingStage,
    processingProgress: $contentViewModel.processingProgress,
    claudeService: claudeService,
    claudePromptManager: claudePromptManager,
    fileClaudeEnabled: $contentViewModel.fileClaudeEnabled,
    fileClaudePromptID: $contentViewModel.fileClaudePromptID,
    onDrop: { url, model, format in
        contentViewModel.transcribe(url: url, model: model, format: format)
    },
    onCancel: {
        contentViewModel.cancelTranscription()
    }
)
```

- [ ] **Step 5: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -10`
Expected: Build succeeds with no errors

- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperWrap/
git commit -m "feat: wire Claude services into app view hierarchy"
```

---

### Task 7: Dictation Flow — Integrate Claude Processing After Transcription

**Files:**
- Modify: `Sources/WhisperWrap/DictationViewModel.swift`

- [ ] **Step 1: Add Claude processing step to the transcribe method**

In `Sources/WhisperWrap/DictationViewModel.swift`, modify the `transcribe(url:)` method (starting at line 521). Replace the existing method:

```swift
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
                let text = try await contentViewModel.transcribeDictation(audioURL: url, model: selectedModel)

                // Check if cancelled before continuing
                if Task.isCancelled { return }

                var finalText = text

                // Claude processing if enabled
                if claudeEnabled,
                   let claudeService = claudeService,
                   let promptManager = claudePromptManager,
                   let promptID = selectedClaudePromptID,
                   let prompt = promptManager.allPrompts.first(where: { $0.id == promptID }) {

                    if showHUD {
                        HUDWindowController.shared.setStatus(.processingWithClaude)
                    }

                    var streamedResult = ""
                    let stream = claudeService.process(text: text, prompt: prompt.prompt)
                    for await chunk in stream {
                        if Task.isCancelled { return }
                        streamedResult += chunk
                        if showHUD {
                            HUDWindowController.shared.updateStreamingText(streamedResult)
                        }
                    }

                    let processed = streamedResult.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !processed.isEmpty {
                        finalText = processed
                    }
                }

                if Task.isCancelled { return }

                self.transcribedText = finalText

                if autoCopy || autoPaste {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finalText, forType: .string)
                }

                if autoPaste {
                    injectText()
                }

            } catch is CancellationError {
                return
            } catch {
                self.transcribedText = "Error: \(error.localizedDescription)"
            }
        }
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/WhisperWrap/DictationViewModel.swift
git commit -m "feat: integrate Claude processing into dictation transcription flow"
```

---

### Task 8: Error Handling and Timeout

**Files:**
- Modify: `Sources/WhisperWrap/ClaudeService.swift`

- [ ] **Step 1: Add timeout wrapper to the process method**

In `Sources/WhisperWrap/ClaudeService.swift`, add a convenience method that wraps `process` with a 30-second timeout and error fallback:

```swift
    /// Process text with a timeout. Returns original text if Claude fails.
    func processWithFallback(text: String, prompt: String, timeout: TimeInterval = 30) async -> (result: String, didFallback: Bool) {
        var accumulated = ""
        let stream = process(text: text, prompt: prompt)

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        }

        let streamTask = Task { () -> String in
            var result = ""
            for await chunk in stream {
                result += chunk
            }
            return result
        }

        // Race: stream completion vs timeout
        let result = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                return await streamTask.value
            }
            group.addTask {
                try? await timeoutTask.value
                return nil // timeout sentinel
            }

            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return nil
        }

        if let result = result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            timeoutTask.cancel()
            return (result.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }

        // Fallback to original text
        streamTask.cancel()
        timeoutTask.cancel()
        return (text, true)
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/WhisperWrap/ClaudeService.swift
git commit -m "feat: add timeout and fallback to Claude processing"
```

---

### Task 9: Build, Test, and Fix

**Files:**
- All modified files

- [ ] **Step 1: Full build**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift build 2>&1`

Fix any compilation errors. Common issues to watch for:
- Missing parameter labels at call sites for updated views
- Type mismatches for optional UUID bindings
- `@MainActor` isolation warnings

- [ ] **Step 2: Run the app and test manually**

Run: `cd /Users/akeslo/Scrypting/WhisperWrap && swift run 2>&1`

Test these scenarios:
1. Settings: Claude toggle OFF by default
2. Toggle ON without claude CLI → shows error message
3. Toggle ON with claude CLI installed → verifies auth → enables section
4. Prompt dropdown shows 3 presets
5. Can type and save a custom prompt
6. Can delete a custom prompt
7. Dictation with Claude OFF → normal behavior
8. Dictation with Claude ON → transcribes then streams through Claude
9. File transcription with Claude ON → processes after Whisper
10. HUD shows streaming text during Claude processing

- [ ] **Step 3: Fix any issues found and commit**

```bash
git add -A
git commit -m "fix: resolve build and runtime issues for Claude integration"
```
