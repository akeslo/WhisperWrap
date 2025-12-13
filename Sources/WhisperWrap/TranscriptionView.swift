import SwiftUI

struct TranscriptionView: View {
    @Binding var consoleOutput: String
    @Binding var isProcessing: Bool
    @Binding var processingStage: String
    @Binding var processingProgress: Double
    @State private var selectedModel: Model = .base
    @State private var selectedFormat: String = "txt"
    @State private var isTargeted: Bool = false
    @State private var droppedFileName: String?
    @State private var showCopiedConfirmation: Bool = false
    @State private var showClearConfirmation: Bool = false

    let formats = ["txt", "srt", "json"]
    let onDrop: (URL, Model, String) -> Void
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            // MARK: - Header & Controls
            HStack(spacing: 15) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Picker("Model", selection: $selectedModel) {
                        ForEach(Model.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(formats, id: \.self) { format in
                            Text(format.uppercased()).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                Spacer()
            }
            .disabled(isProcessing)
            
            // MARK: - Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [10]))

                if isProcessing {
                    VStack(spacing: 20) {
                        HStack {
                            Spacer()
                            Button(action: {
                                onCancel?()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel Transcription")
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)

                        ZStack {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 4)
                                .frame(width: 80, height: 80)

                            Circle()
                                .trim(from: 0, to: processingProgress > 0 ? processingProgress : 0.05)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.5), value: processingProgress)

                            Image(systemName: "waveform")
                                .font(.largeTitle)
                                .foregroundColor(.accentColor)
                                .symbolEffect(.pulse)
                        }

                        VStack(spacing: 5) {
                            Text(processingStage.isEmpty ? "Processing..." : processingStage)
                                .font(.headline)

                            if let fileName = droppedFileName {
                                Text(fileName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if processingProgress > 0 {
                                Text("\(Int(processingProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } else {
                    VStack(spacing: 15) {
                        Image(systemName: isTargeted ? "arrow.down.circle.fill" : "waveform.circle")
                            .font(.system(size: 60))
                            .foregroundColor(isTargeted ? .accentColor : .secondary)
                            .symbolEffect(.bounce, value: isTargeted)
                        
                        VStack(spacing: 5) {
                            Text("Drop Audio File Here")
                                .font(.title3)
                                .fontWeight(.medium)
                            
                            Text("Supports MP3, WAV, M4A, FLAC")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(height: 240)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard !isProcessing else { return false }
                guard let provider = providers.first else { return false }
                let typeIdentifier = "public.file-url"
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (urlData, error) in
                    guard let urlData = urlData as? Data else { return }
                    DispatchQueue.main.async {
                        let url = URL(dataRepresentation: urlData, relativeTo: nil)
                        guard let url = url else { return }
                        droppedFileName = url.lastPathComponent
                        onDrop(url, selectedModel, selectedFormat)
                    }
                }
                return true
            }
            .animation(.easeInOut, value: isTargeted)
            .animation(.easeInOut, value: isProcessing)
            
            // MARK: - Terminal Output
            VStack(spacing: 0) {
                HStack {
                    Label("Log Output", systemImage: "terminal.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !consoleOutput.isEmpty {
                        HStack(spacing: 10) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(consoleOutput, forType: .string)
                                showCopiedConfirmation = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showCopiedConfirmation = false
                                }
                            } label: {
                                Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Copy Output")

                            Button {
                                showClearConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Clear Output")
                            .confirmationDialog("Clear Output", isPresented: $showClearConfirmation) {
                                Button("Clear", role: .destructive) {
                                    consoleOutput = ""
                                    droppedFileName = nil
                                }
                                Button("Cancel", role: .cancel) { }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(consoleOutput.isEmpty ? "Ready to transcribe..." : consoleOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(consoleOutput.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                            .id("outputBottom")
                    }
                    .onChange(of: consoleOutput) { _, _ in
                        withAnimation {
                            proxy.scrollTo("outputBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .frame(minHeight: 120)
        }
        .padding()
        .onAppear { }
    }
}
