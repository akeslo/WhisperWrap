import SwiftUI

struct TranscriptionView: View {
    @Binding var consoleOutput: String
    @Binding var isProcessing: Bool
    @Binding var processingStage: String
    @Binding var processingProgress: Double
    @ObservedObject var claudeService: ClaudeService
    @ObservedObject var claudePromptManager: ClaudePromptManager
    @Binding var fileClaudeEnabled: Bool
    @Binding var fileClaudePromptID: UUID?
    // Persisted so the file-transcription model choice survives app restarts (U20) —
    // previously a plain @State that silently reset to .base every launch.
    @AppStorage("fileTranscriptionModel") private var selectedModel: Model = .base
    @State private var selectedFormat: String = "txt"
    @State private var isTargeted: Bool = false
    @State private var droppedFileName: String?
    @State private var showCopiedConfirmation: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var isCheckingClaude: Bool = false
    @State private var claudeSetupError: String?
    @State private var showClaudeSetupAlert: Bool = false

    let formats = ["txt", "srt", "json"]
    let onDrop: (URL, Model, String, Bool) -> Void
    var onCancel: (() -> Void)?

    var body: some View {
        Page(title: "Files", lede: "Drop an audio file to transcribe it to text, subtitles, or JSON.") {
            Panel(title: "Output") {
                SettingRow(label: "Whisper model") {
                    Picker("Whisper model", selection: $selectedModel) {
                        ForEach(Model.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                SettingRow(label: "Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(formats, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                SettingRow(label: "Refine with Claude", detail: "Asks before sending each file's transcript") {
                    HStack(spacing: 8) {
                        if isCheckingClaude { TallyLight(color: Theme.amber, pulsing: true) }
                        Toggle("Refine with Claude", isOn: Binding(
                            get: { fileClaudeEnabled },
                            set: { newValue in
                                if newValue && !claudeService.isConnected { enableClaude() } else { fileClaudeEnabled = newValue }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
                if fileClaudeEnabled {
                    SettingRow(label: "Prompt") {
                        Picker("Prompt", selection: $fileClaudePromptID) {
                            ForEach(claudePromptManager.allPrompts) { Text($0.name).tag($0.id as UUID?) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
            }
            .disabled(isProcessing)
            .alert("Claude Isn't Ready", isPresented: $showClaudeSetupAlert) {
                Button("OK") { }
            } message: {
                Text(claudeSetupError ?? "Check the Claude CLI on the Prompts page.")
            }

            dropZone

            Panel(title: "Log") {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(consoleOutput.isEmpty ? "Transcripts and progress appear here." : consoleOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(consoleOutput.isEmpty ? Theme.textDim : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("outputBottom")
                    }
                    .frame(minHeight: 120, maxHeight: 240)
                    .onChange(of: consoleOutput) { _, _ in
                        withAnimation { proxy.scrollTo("outputBottom", anchor: .bottom) }
                    }
                }
                HStack {
                    Spacer()
                    Button(showCopiedConfirmation ? "Copied" : "Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(consoleOutput, forType: .string)
                        showCopiedConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showCopiedConfirmation = false }
                    }
                    Button("Clear Log") { showClearConfirmation = true }
                        .confirmationDialog("Clear the log?", isPresented: $showClearConfirmation) {
                            Button("Clear Log", role: .destructive) {
                                consoleOutput = ""
                                droppedFileName = nil
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                }
                .disabled(consoleOutput.isEmpty)
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? Theme.raised : Theme.raised.opacity(0.5))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isTargeted ? Theme.text.opacity(0.5) : Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [6]))

            if isProcessing {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TallyLight(color: Theme.amber, pulsing: true)
                        Text(processingStage.isEmpty ? "Transcribing" : processingStage)
                            .foregroundStyle(Theme.text)
                        if processingProgress > 0 {
                            Text("\(Int(processingProgress * 100))%")
                                .font(Theme.numerals(13))
                                .foregroundStyle(Theme.amber)
                        }
                    }
                    if let fileName = droppedFileName {
                        Text(fileName).font(.caption).foregroundStyle(Theme.textDim)
                    }
                    ProgressView(value: processingProgress > 0 ? processingProgress : nil)
                        .frame(width: 240)
                        .tint(Theme.amber)
                    Button("Cancel Transcription") { onCancel?() }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: isTargeted ? "arrow.down.circle" : "waveform")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(isTargeted ? Theme.text : Theme.textDim)
                    Text("Drop an audio file")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Text("MP3, WAV, M4A, or FLAC")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .frame(height: 200)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard !isProcessing, let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, _) in
                guard let urlData = urlData as? Data else { return }
                DispatchQueue.main.async {
                    guard let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    droppedFileName = url.lastPathComponent
                    if fileClaudeEnabled {
                        let alert = NSAlert()
                        alert.messageText = "Send this transcript to Claude?"
                        alert.informativeText = "The transcribed text of \(url.lastPathComponent) goes to Anthropic for refining."
                        alert.addButton(withTitle: "Transcribe and Refine")
                        alert.addButton(withTitle: "Transcribe Only")
                        alert.addButton(withTitle: "Cancel")
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            onDrop(url, selectedModel, selectedFormat, true)
                        } else if response == .alertSecondButtonReturn {
                            onDrop(url, selectedModel, selectedFormat, false)
                        }
                    } else {
                        onDrop(url, selectedModel, selectedFormat, false)
                    }
                }
            }
            return true
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private func enableClaude() {
        isCheckingClaude = true
        Task {
            defer { isCheckingClaude = false }
            switch await claudeService.verifyClaudeSetup() {
            case .success:
                fileClaudeEnabled = true
            case .failure(let message):
                claudeSetupError = message
                showClaudeSetupAlert = true
            }
        }
    }
}
