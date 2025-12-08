import SwiftUI
import UniformTypeIdentifiers

struct TTSView: View {
    @ObservedObject var viewModel: TTSViewModel
    @State private var isTargeted: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var showFileExporter: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Header
            HStack {
                Label("Text to Speech", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .font(.headline)
                Spacer()
                
                Button(action: { showFileImporter = true }) {
                    Label("Import Text File", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText, .json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.loadText(from: url)
                    }
                case .failure(let error):
                    LoggerService.shared.debug("File import failed: \(error)")
                }
            }
            
            // MARK: - Engine Selector
            Picker("Engine", selection: $viewModel.selectedEngine) {
                ForEach(TTSEngine.allCases, id: \.self) { engine in
                    Text(engine.rawValue).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: viewModel.selectedEngine) { _, engine in
                if engine == .elevenLabs {
                    Task { await viewModel.fetchElevenLabsUserInfo() }
                }
            }
            
            // MARK: - ElevenLabs Config
            if viewModel.selectedEngine == .elevenLabs {
                HStack {
                    SecureField("ElevenLabs API Key", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    if viewModel.isFetchingVoices {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 20)
                    } else {
                        Button(action: { viewModel.fetchElevenLabsVoices() }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .help("Reload Voices & Credits")
                    }
                    
                    Text(viewModel.creditsDisplayString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
                .padding(.horizontal)
            }
            
            // MARK: - Voice & Speed Controls
            HStack(spacing: 20) {
                // Voice Picker
                HStack {
                    Image(systemName: "person.wave.2.fill")
                        .foregroundColor(.secondary)
                    
                    if viewModel.selectedEngine == .system {
                        Picker("Voice", selection: $viewModel.selectedSystemVoice) {
                            ForEach(viewModel.availableSystemVoices, id: \.identifier) { voice in
                                Text(voice.name).tag(Optional(voice))
                            }
                        }
                        .frame(minWidth: 150)
                    } else {
                        Picker("Voice", selection: $viewModel.selectedElevenLabsVoice) {
                            ForEach(viewModel.availableElevenLabsVoices, id: \.voice_id) { voice in
                                Text(voice.name).tag(Optional(voice))
                            }
                        }
                        .frame(minWidth: 150)
                        .onAppear {
                            if viewModel.availableElevenLabsVoices.isEmpty && !viewModel.apiKey.isEmpty {
                                viewModel.fetchElevenLabsVoices()
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                // Speed & Volume Controls
                HStack(spacing: 20) {
                    // System Speed
                    if viewModel.selectedEngine == .system {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.secondary)
                            
                            Slider(value: $viewModel.speechRate, in: 0.0...1.0)
                                .frame(width: 80)
                                .help("Speech Rate")
                            
                            Text(String(format: "%.1f", viewModel.speechRate))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Volume Control (Global)
                    HStack {
                        Image(systemName: viewModel.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundColor(.secondary)
                        
                        Slider(value: $viewModel.volume, in: 0.0...1.0)
                            .frame(width: 80)
                            .onChange(of: viewModel.volume) {
                                viewModel.updateVolume()
                            }
                            .help("Volume")
                        
                        Text("\(Int(viewModel.volume * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 35)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            
            // MARK: - Text Input Area
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                if viewModel.text.isEmpty {
                    Text("Paste text here or import a file...")
                        .foregroundColor(.secondary)
                        .padding()
                }
                
                TextEditor(text: $viewModel.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .scrollContentBackground(.hidden) // Remove default background
                    .background(Color.clear)
                
                // Character Count Overlay
                if viewModel.selectedEngine == .elevenLabs {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            
                            if viewModel.text.count > 10_000 {
                                Button("Truncate to Limit") {
                                    viewModel.truncateText()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            }
                            
                            Text("\(viewModel.text.count) / 10,000")
                                .font(.caption)
                                .foregroundColor(viewModel.text.count > 10_000 ? .red : .secondary)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor).opacity(0.8)))
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxHeight: .infinity) // Allow expansion
            .layoutPriority(1) // Ensure it takes available space
            
            if let source = viewModel.contentSource {
                HStack {
                    Image(systemName: "doc")
                    Text("Loaded from: \(source)")
                        .font(.caption)
                    Button(action: { viewModel.contentSource = nil }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal)
            }
            
            // MARK: - Controls
            HStack(spacing: 30) {
                Button(action: {
                    if viewModel.isSpeaking {
                         if viewModel.isPaused {
                             viewModel.resume()
                         } else {
                             viewModel.pause()
                         }
                    } else {
                        viewModel.speak()
                    }
                }) {
                    if viewModel.isDownloadingAudio {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: viewModel.isSpeaking && !viewModel.isPaused ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .help(viewModel.isSpeaking && !viewModel.isPaused ? "Pause" : "Speak")
                .disabled(viewModel.text.isEmpty || viewModel.isDownloadingAudio || (viewModel.selectedEngine == .elevenLabs && viewModel.apiKey.isEmpty))
                
                Button(action: { viewModel.stop() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(viewModel.isSpeaking ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Stop")
                .disabled(!viewModel.isSpeaking)
                
                Button(action: {
                    if viewModel.lastAudioData != nil {
                        showFileExporter = true
                    } else {
                        viewModel.errorMessage = "No audio to save. Please play the text first to generate audio."
                    }
                }) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 30))
                        .foregroundColor(viewModel.lastAudioData == nil ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .help("Save Audio to File")
                
                Button(action: { viewModel.text = "" }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Text")
            }
            .padding()
            .fileExporter(
                isPresented: $showFileExporter,
                document: AudioDocument(data: viewModel.lastAudioData),
                contentType: .audio,
                defaultFilename: "tts_output.mp3"
            ) { result in
                switch result {
                case .success(let url):
                    viewModel.saveLastAudio(to: url)
                case .failure(let error):
                    viewModel.errorMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            
            if viewModel.isDownloadingAudio {
                VStack(spacing: 4) {
                    ProgressView(value: viewModel.selectedEngine == .elevenLabs ? viewModel.downloadProgress : nil)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    
                    Text(viewModel.downloadProgress > 0 ? "Generating Audio (\(Int(viewModel.downloadProgress * 100))%)" : "Generating Audio...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
                .padding(.bottom, 10)
            }
            
            Spacer(minLength: 20)
        }
        .padding()
        .alert(item: Binding<AlertError?>(
            get: { viewModel.errorMessage.map { AlertError(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { error in
            Alert(title: Text("Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
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
