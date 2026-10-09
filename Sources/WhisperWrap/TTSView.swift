import SwiftUI
import UniformTypeIdentifiers

struct TTSView: View {
    @ObservedObject var viewModel: TTSViewModel
    @State private var isTargeted: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showFileExporter: Bool = false
    
    private var canSpeak: Bool {
        !viewModel.text.isEmpty && !viewModel.isDownloadingAudio
            && !(viewModel.selectedEngine == .elevenLabs && viewModel.apiKey.isEmpty)
    }

    var body: some View {
        Page(title: "Voice", lede: "Read text aloud with a system voice or ElevenLabs.") {
            Panel(title: "Voice") {
                SettingRow(label: "Engine") {
                    Picker("Engine", selection: $viewModel.selectedEngine) {
                        ForEach(TTSEngine.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: viewModel.selectedEngine) { _, engine in
                        if engine == .elevenLabs { Task { await viewModel.fetchElevenLabsUserInfo() } }
                    }
                }
                if viewModel.selectedEngine == .elevenLabs {
                    SettingRow(label: "API key", detail: viewModel.creditsDisplayString) {
                        SecureField("ElevenLabs API key", text: $viewModel.apiKey)
                            .frame(width: 200)
                        Button("Reload Voices") { viewModel.fetchElevenLabsVoices() }
                            .disabled(viewModel.isFetchingVoices)
                    }
                }
                SettingRow(label: "Voice") {
                    if viewModel.selectedEngine == .system {
                        Picker("Voice", selection: $viewModel.selectedSystemVoice) {
                            ForEach(viewModel.availableSystemVoices, id: \.identifier) { Text($0.name).tag(Optional($0)) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    } else {
                        Picker("Voice", selection: $viewModel.selectedElevenLabsVoice) {
                            ForEach(viewModel.availableElevenLabsVoices, id: \.voice_id) { Text($0.name).tag(Optional($0)) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onAppear {
                            if viewModel.availableElevenLabsVoices.isEmpty && !viewModel.apiKey.isEmpty {
                                viewModel.fetchElevenLabsVoices()
                            }
                        }
                    }
                }
                if viewModel.selectedEngine == .system {
                    SettingRow(label: "Rate") {
                        Slider(value: $viewModel.speechRate, in: 0.0...1.0).frame(width: 160)
                        Text(String(format: "%.1f", viewModel.speechRate))
                            .font(Theme.numerals(12)).foregroundStyle(Theme.amber).frame(width: 36, alignment: .trailing)
                    }
                }
                SettingRow(label: "Volume") {
                    Slider(value: $viewModel.volume, in: 0.0...1.0)
                        .frame(width: 160)
                        .onChange(of: viewModel.volume) { viewModel.updateVolume() }
                    Text("\(Int(viewModel.volume * 100))%")
                        .font(Theme.numerals(12)).foregroundStyle(Theme.amber).frame(width: 36, alignment: .trailing)
                }
            }

            Panel(title: "Text") {
                ZStack(alignment: .topLeading) {
                    if viewModel.text.isEmpty {
                        Text("Paste text here, or import a file.")
                            .foregroundStyle(Theme.textDim)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $viewModel.text)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                }
                .frame(minHeight: 200)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))

                HStack(spacing: 8) {
                    if let source = viewModel.contentSource {
                        Text("From \(source)").font(.caption).foregroundStyle(Theme.textDim).lineLimit(1)
                        Button("Forget Source") { viewModel.contentSource = nil }.controlSize(.small)
                    }
                    Spacer()
                    if viewModel.selectedEngine == .elevenLabs {
                        if viewModel.text.count > 10_000 {
                            Button("Trim to 10,000 Characters") { viewModel.truncateText() }.controlSize(.small)
                        }
                        Text("\(viewModel.text.count) / 10,000")
                            .font(Theme.numerals(11))
                            .foregroundStyle(viewModel.text.count > 10_000 ? Theme.tx : Theme.amber)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if viewModel.isSpeaking {
                            viewModel.isPaused ? viewModel.resume() : viewModel.pause()
                        } else {
                            viewModel.speak()
                        }
                    } label: {
                        Label(viewModel.isSpeaking && !viewModel.isPaused ? "Pause" : (viewModel.isPaused ? "Resume" : "Speak"),
                              systemImage: viewModel.isSpeaking && !viewModel.isPaused ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSpeak)

                    Button("Stop") { viewModel.stop() }
                        .disabled(!viewModel.isSpeaking)

                    if viewModel.isDownloadingAudio {
                        TallyLight(color: Theme.amber, pulsing: true)
                        Text("Generating audio").foregroundStyle(Theme.textDim)
                        if viewModel.downloadProgress > 0 {
                            Text("\(Int(viewModel.downloadProgress * 100))%")
                                .font(Theme.numerals(12)).foregroundStyle(Theme.amber)
                        }
                    }
                    Spacer()
                    Button("Import Text File…") { showFileImporter = true }
                    Button("Save Audio…") { showFileExporter = true }
                        .disabled(viewModel.lastAudioData == nil)
                        .help("Play the text first to generate audio")
                    Button("Clear Text") { viewModel.text = "" }
                        .disabled(viewModel.text.isEmpty)
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.plainText, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { viewModel.loadText(from: url) }
            case .failure(let error):
                LoggerService.shared.debug("File import failed: \(error)")
            }
        }
        .fileExporter(isPresented: $showFileExporter, document: AudioDocument(data: viewModel.lastAudioData),
                      contentType: .audio, defaultFilename: "tts_output.mp3") { result in
            switch result {
            case .success(let url): viewModel.saveLastAudio(to: url)
            case .failure(let error): viewModel.errorMessage = "Couldn't save the audio: \(error.localizedDescription)"
            }
        }
        .alert(item: Binding<AlertError?>(
            get: { viewModel.errorMessage.map { AlertError(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { error in
            Alert(title: Text("Voice Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
        }
    }
}

struct AlertError: Identifiable {
    let id = UUID()
    let message: String
}

struct AudioDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.audio] }
    
    var data: Data?
    
    init(data: Data?) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data ?? Data())
    }
}
