import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    
    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    @StateObject private var prefetch = PrefetchManager()
    @StateObject private var permissions = PermissionsManager.shared
    @StateObject private var ttsViewModel = TTSViewModel()
    @State private var selectedTab = 4

    var body: some View {
        TabView(selection: $selectedTab) {
            DictationView()
                .environmentObject(viewModel)
                .tabItem {
                    Label("Dictation", systemImage: "mic.fill")
                }
                .tag(4)
            
            TranscriptionView(
                consoleOutput: $viewModel.consoleOutput,
                isProcessing: $viewModel.isProcessing,
                processingStage: $viewModel.processingStage,
                processingProgress: $viewModel.processingProgress,
                onDrop: { url, model, format in
                    viewModel.transcribe(url: url, model: model, format: format)
                }
            )
            .tabItem {
                Label("Transcribe", systemImage: "waveform")
            }
            .tag(0)

            TTSView(viewModel: ttsViewModel)
                .tabItem {
                    Label("Text to Speech", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill")
                }
                .tag(3)

            PrefetchModelsView()
                .environmentObject(prefetch)
                .tabItem {
                    Label("Models", systemImage: "server.rack")
                }
                .tag(1)

            DiagnosticsView()
                .environmentObject(viewModel)
                .environmentObject(prefetch)
                .tabItem {
                    Label("Diagnostics", systemImage: "wrench")
                }
                .tag(2)
        }
        .onChange(of: viewModel.whisperInstalled) { _, installed in
            if installed {
                prefetch.refresh()
                prefetch.refreshSizes()
                
                // Request permissions after the setup sheet disappears (with delay)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    PermissionsManager.shared.requestAllPermissions()
                }
            }
        }
        .onChange(of: viewModel.requestedTab) { _, newTab in
            if let tab = newTab {
                selectedTab = tab
                viewModel.requestedTab = nil // Reset after switching
            }
        }
        .onAppear {
            if let tab = viewModel.requestedTab {
                selectedTab = tab
                viewModel.requestedTab = nil
            }
            if viewModel.whisperInstalled {
                 // Trigger permissions if already installed (skipped the transition)
                 DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                     PermissionsManager.shared.requestAllPermissions()
                 }
            }
        }
        .sheet(isPresented: Binding(
            get: { !viewModel.whisperInstalled },
            set: { _ in }
        )) {
            DependencyView(viewModel: viewModel)
        }
        .navigationTitle("WhisperWrap")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permissions whenever app becomes active (e.g. returning from System Settings)
            PermissionsManager.shared.checkPermissions()
        }
        .alert(isPresented: $permissions.showMicrophoneDeniedAlert) {
            Alert(
                title: Text("Microphone Access Denied"),
                message: Text("WhisperWrap needs microphone access to dictate text. Please enable it in System Settings."),
                primaryButton: .default(Text("Open Settings"), action: {
                    permissions.openSystemSettings()
                }),
                secondaryButton: .cancel()
            )
        }
    }
}

struct DependencyView: View {
    @ObservedObject var viewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("WhisperWrap")
                .font(.largeTitle)

            VStack(spacing: 8) {
                Text("Speech Engine Setup")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("WhisperWrap will set up a private Python environment and install faster-whisper automatically.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                DependencyStatusView(name: "faster-whisper", isInstalled: viewModel.whisperInstalled)
            }

            if !viewModel.whisperInstalled {
                if viewModel.isCheckingEnv {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking installation...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Set Up Speech Engine") {
                        viewModel.installDependencies()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isInstalling || viewModel.isCheckingEnv)
                }
            }

            if viewModel.isInstalling {
                ProgressView()
                    .scaleEffect(1.2)
            }

            // Always show output for debugging
            if !viewModel.installationOutput.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Installation Log:")
                        .font(.headline)

                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(viewModel.installationOutput)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("logBottom")
                        }
                        .onChange(of: viewModel.installationOutput) { _, _ in
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
                    }
                    .frame(height: 200)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)

                    Button("Copy to Clipboard") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.installationOutput, forType: .string)
                        #endif
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct DependencyStatusView: View {
    let name: String
    let isInstalled: Bool
    
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isInstalled ? .green : .red)
        }
    }
}
