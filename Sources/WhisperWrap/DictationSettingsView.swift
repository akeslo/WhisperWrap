import SwiftUI
import Carbon

struct DictationSettingsView: View {
    @ObservedObject var viewModel: DictationViewModel
    @ObservedObject var claudeService: ClaudeService
    @ObservedObject var claudePromptManager: ClaudePromptManager

    @State private var claudeSetupError: String?
    @State private var showClaudeSetupAlert = false
    @State private var isCheckingClaude = false
    @State private var customPromptName: String = ""
    @State private var customPromptText: String = ""
    @State private var editingPromptText: String = ""
    @State private var promptTextModified: Bool = false

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
                                // Prompt for directory if turning on and no directory set
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
                            if newValue && !claudeService.isConnected {
                                // First-time enable: check CLI + auth
                                enableClaude()
                            } else {
                                viewModel.claudeEnabled = newValue
                            }
                        }
                    ))

                    Spacer()

                    if isCheckingClaude {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if claudeService.isConnected && viewModel.claudeEnabled {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if viewModel.claudeEnabled {
                    Toggle("Prompt selection on each use", isOn: $viewModel.promptSelectionMode)
                        .help("Show a 5-second prompt picker in the HUD after each transcription")

                    HStack {
                        Text("Model")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $viewModel.selectedClaudeModel) {
                            Text("Haiku").tag("haiku")
                            Text("Sonnet").tag("sonnet")
                            Text("Opus").tag("opus")
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Spacer()
                    }

                    HStack {
                        Text("Prompt")
                            .frame(width: 100, alignment: .leading)
                        Picker("", selection: $viewModel.selectedClaudePromptID) {
                            ForEach(claudePromptManager.allPrompts) { prompt in
                                Text(prompt.name).tag(prompt.id as UUID?)
                            }
                            Divider()
                            Text("Custom...").tag(nil as UUID?)
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: viewModel.selectedClaudePromptID) { _, newValue in
                            loadPromptText(for: newValue)
                        }

                        if let selectedID = viewModel.selectedClaudePromptID,
                           let selected = claudePromptManager.allPrompts.first(where: { $0.id == selectedID }),
                           !selected.isBuiltin {
                            Button(role: .destructive) {
                                claudePromptManager.deleteCustomPrompt(selected)
                                viewModel.selectedClaudePromptID = ClaudePrompt.builtinPolish.id
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        Spacer()
                    }

                    // Prompt text editor for selected prompts
                    if let selectedID = viewModel.selectedClaudePromptID,
                       let selected = claudePromptManager.allPrompts.first(where: { $0.id == selectedID }) {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $editingPromptText)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 60, maxHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .onChange(of: editingPromptText) { _, newValue in
                                    promptTextModified = newValue != selected.prompt
                                }

                            HStack {
                                if selected.isBuiltin && claudePromptManager.builtinOverrides[selected.id.uuidString] != nil {
                                    Button("Reset to Default") {
                                        claudePromptManager.resetBuiltinPrompt(selected)
                                        loadPromptText(for: viewModel.selectedClaudePromptID)
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                if promptTextModified {
                                    Button("Save") {
                                        claudePromptManager.updatePrompt(selected, newText: editingPromptText)
                                        promptTextModified = false
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    if viewModel.selectedClaudePromptID == nil {
                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Save Custom Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("Name", text: $customPromptName)
                                    .frame(width: 120)
                                TextField("Prompt instructions...", text: $customPromptText)
                                Button("Save") {
                                    guard !customPromptName.isEmpty, !customPromptText.isEmpty else { return }
                                    claudePromptManager.saveCustomPrompt(name: customPromptName, prompt: customPromptText)
                                    if let newPrompt = claudePromptManager.allPrompts.last {
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
            }
            .padding(8)
        }
        .padding(.horizontal)
        .onAppear {
            loadPromptText(for: viewModel.selectedClaudePromptID)
        }
        .alert("Claude Setup Error", isPresented: $showClaudeSetupAlert) {
            Button("OK") { }
        } message: {
            Text(claudeSetupError ?? "Unknown error")
        }
    }

    private func loadPromptText(for promptID: UUID?) {
        guard let id = promptID,
              let prompt = claudePromptManager.allPrompts.first(where: { $0.id == id }) else {
            editingPromptText = ""
            promptTextModified = false
            return
        }
        editingPromptText = prompt.prompt
        promptTextModified = false
    }

    private func enableClaude() {
        isCheckingClaude = true
        Task {
            defer { isCheckingClaude = false }

            // Check CLI availability
            guard await claudeService.checkAvailability() != nil else {
                claudeSetupError = "Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
                showClaudeSetupAlert = true
                return
            }

            // Verify auth
            let authed = await claudeService.verifyAuth()
            if authed {
                viewModel.claudeEnabled = true
            } else {
                claudeSetupError = claudeService.authError ?? "Claude CLI is not authenticated. Run 'claude' in your terminal to log in."
                showClaudeSetupAlert = true
            }
        }
    }
}

// MARK: - Hotkey Recorder View
struct HotkeyRecorderView: View {
    @ObservedObject var viewModel: DictationViewModel
    @State private var isRecording = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: {
            isRecording = true
            isFocused = true
        }) {
            Text(isRecording ? "Press keys..." : viewModel.hotkeyDisplayString)
                .foregroundColor(isRecording ? .blue : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(isRecording ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.blue : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .onKeyPress { keyPress in
            guard isRecording else { return .ignored }

            // Convert SwiftUI key to Carbon key code
            if let keyCode = keyCodeFromKeyEquivalent(keyPress.key) {
                var modifiers: Int = 0
                if keyPress.modifiers.contains(.command) { modifiers |= cmdKey }
                if keyPress.modifiers.contains(.shift) { modifiers |= shiftKey }
                if keyPress.modifiers.contains(.option) { modifiers |= optionKey }
                if keyPress.modifiers.contains(.control) { modifiers |= controlKey }

                // Require at least one modifier
                if modifiers != 0 {
                    viewModel.setHotkey(keyCode: keyCode, modifiers: modifiers)
                    isRecording = false
                    isFocused = false
                    return .handled
                }
            }
            return .ignored
        }
        .onExitCommand {
            isRecording = false
            isFocused = false
        }
    }

    private func keyCodeFromKeyEquivalent(_ key: KeyEquivalent) -> Int? {
        // Map common keys to Carbon key codes
        let keyMap: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ]
        return keyMap[key.character]
    }
}
