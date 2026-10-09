import SwiftUI
import Carbon

struct DictationSettingsView: View {
    @ObservedObject var viewModel: DictationViewModel
    @ObservedObject var claudePromptManager: ClaudePromptManager

    var body: some View {
        Panel(title: "Hotkeys") {
            SettingRow(label: "Dictate", detail: "Click, then press a new combination") {
                HotkeyRecorderView(viewModel: viewModel)
            }
            SettingRow(label: "Refine last dictation", detail: "Replaces the pasted text with the refined version") {
                KeyCap(keys: "⌥⌘R")
            }
            SettingRow(label: "Show last result window") {
                KeyCap(keys: "⌥⇧V")
            }
        }

        Panel(title: "Speech") {
            SettingRow(label: "Engine") {
                Picker("Engine", selection: $viewModel.dictationEngine) {
                    ForEach(DictationEngine.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            if viewModel.dictationEngine == .whisper {
                SettingRow(label: "Whisper model") {
                    Picker("Whisper model", selection: $viewModel.selectedModel) {
                        ForEach(Model.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
            SettingRow(label: "Microphone") {
                Picker("Microphone", selection: $viewModel.selectedAudioDeviceID) {
                    ForEach(viewModel.availableAudioDevices, id: \.id) { device in
                        Text(device.name).tag(device.id as String?)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }

        Panel(title: "Refine") {
            SettingRow(label: "Default prompt", detail: "Edit prompts on the Prompts page") {
                Picker("Default prompt", selection: $viewModel.selectedClaudePromptID) {
                    ForEach(claudePromptManager.allPrompts) { prompt in
                        Text(prompt.name).tag(prompt.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            SettingRow(label: "Claude model") {
                Picker("Claude model", selection: $viewModel.selectedClaudeModel) {
                    Text("Haiku").tag("haiku")
                    Text("Sonnet").tag("sonnet")
                    Text("Opus").tag("opus")
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Text("Refining sends the transcript to Claude through your local claude CLI.")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }

        Panel(title: "Behavior") {
            SettingRow(label: "Keep text on clipboard", detail: "Off restores your previous clipboard after pasting") {
                Toggle("Keep text on clipboard", isOn: $viewModel.autoCopy).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(label: "Show recording HUD") {
                Toggle("Show recording HUD", isOn: $viewModel.showHUD).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(label: "Launch at login") {
                Toggle("Launch at login", isOn: $viewModel.launchAtLogin).labelsHidden().toggleStyle(.switch)
            }
            SettingRow(label: "Save recordings") {
                Toggle("Save recordings", isOn: Binding(
                    get: { viewModel.saveRecordings },
                    set: { newValue in
                        viewModel.saveRecordings = newValue
                        if newValue && viewModel.recordingsSaveDirectory == nil {
                            viewModel.selectRecordingsDirectory()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if viewModel.saveRecordings, let saveDir = viewModel.recordingsSaveDirectory {
                SettingRow(label: "Recordings folder") {
                    Text(saveDir.path)
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .trailing)
                    Button("Change…") { viewModel.selectRecordingsDirectory() }
                }
            }
        }
    }
}

/// Prompts page: pick a prompt, edit its text, reset builtins, add or delete custom ones.
struct PromptsView: View {
    @ObservedObject var claudeService: ClaudeService
    @ObservedObject var claudePromptManager: ClaudePromptManager

    @State private var selectedID: UUID?
    @State private var confirmingDelete = false
    @State private var draft = ""
    @State private var newName = ""
    @State private var newText = ""
    @State private var isChecking = false
    @State private var checkMessage: String?

    private var selected: ClaudePrompt? {
        claudePromptManager.allPrompts.first { $0.id == selectedID }
    }

    var body: some View {
        Page(title: "Prompts", lede: "Instructions Claude follows when you refine a dictation or a file.") {
            Panel(title: "Library") {
                VStack(spacing: 2) {
                    ForEach(claudePromptManager.allPrompts) { prompt in
                        Button {
                            select(prompt)
                        } label: {
                            HStack {
                                Text(prompt.name).foregroundStyle(Theme.text)
                                Spacer()
                                if prompt.isBuiltin {
                                    Text(claudePromptManager.builtinOverrides[prompt.id.uuidString] != nil ? "Built-in, edited" : "Built-in")
                                        .font(.caption).foregroundStyle(Theme.textDim)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(prompt.id == selectedID ? Theme.ground : .clear,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let prompt = selected {
                Panel(title: prompt.name) {
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 120, maxHeight: 220)
                        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
                    HStack {
                        if prompt.isBuiltin {
                            Button("Reset to Default") {
                                claudePromptManager.resetBuiltinPrompt(prompt)
                                reload()
                            }
                            .disabled(claudePromptManager.builtinOverrides[prompt.id.uuidString] == nil)
                        } else {
                            Button("Delete Prompt", role: .destructive) {
                                confirmingDelete = true
                            }
                            .confirmationDialog(
                                "Delete \"\(prompt.name)\"?",
                                isPresented: $confirmingDelete,
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) {
                                    claudePromptManager.deleteCustomPrompt(prompt)
                                    selectedID = nil
                                    draft = ""
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("This custom prompt will be permanently removed.")
                            }
                        }
                        Spacer()
                        Button("Save Changes") {
                            claudePromptManager.updatePrompt(prompt, newText: draft)
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(draft == prompt.prompt || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Panel(title: "New prompt") {
                TextField("Name", text: $newName)
                TextField("Instructions, e.g. Rewrite as a friendly Slack message", text: $newText, axis: .vertical)
                    .lineLimit(2...5)
                HStack {
                    Spacer()
                    Button("Add Prompt") {
                        claudePromptManager.saveCustomPrompt(name: newName, prompt: newText)
                        if let added = claudePromptManager.allPrompts.last { select(added) }
                        newName = ""
                        newText = ""
                    }
                    .disabled(newName.isEmpty || newText.isEmpty)
                }
            }

            Panel(title: "Claude CLI") {
                SettingRow(label: "CLI path", detail: "Leave empty to find claude on your PATH") {
                    TextField("/usr/local/bin/claude", text: $claudeService.customClaudePath)
                        .frame(width: 240)
                }
                HStack(spacing: 8) {
                    if isChecking {
                        TallyLight(color: Theme.amber, pulsing: true)
                        Text("Checking…").foregroundStyle(Theme.textDim)
                    } else if let checkMessage {
                        Text(checkMessage).font(.caption).foregroundStyle(Theme.textDim)
                    } else if claudeService.isConnected {
                        TallyLight(color: Theme.landed)
                        Text("Signed in").foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Button("Check Connection") { check() }
                        .disabled(isChecking)
                }
            }
        }
        .onAppear {
            if selectedID == nil, let first = claudePromptManager.allPrompts.first { select(first) }
        }
    }

    private func select(_ prompt: ClaudePrompt) {
        selectedID = prompt.id
        draft = prompt.prompt
    }

    private func reload() {
        draft = selected?.prompt ?? ""
    }

    private func check() {
        isChecking = true
        checkMessage = nil
        Task {
            defer { isChecking = false }
            switch await claudeService.verifyClaudeSetup() {
            case .success: checkMessage = nil
            case .failure(let message): checkMessage = message
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
            // Focusable only while recording, so it can't grab initial focus and scroll the page.
            DispatchQueue.main.async { isFocused = true }
        }) {
            Text(isRecording ? "Press new keys…" : viewModel.hotkeyDisplayString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(isRecording ? Theme.text.opacity(0.6) : Theme.hairline)
                )
        }
        .buttonStyle(.plain)
        .focusable(isRecording)
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
