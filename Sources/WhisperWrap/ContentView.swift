import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @EnvironmentObject var claudeService: ClaudeService
    @EnvironmentObject var claudePromptManager: ClaudePromptManager

    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @StateObject private var prefetch = PrefetchManager()
    @StateObject private var ttsViewModel = TTSViewModel()
    @State private var selectedTab = 4

    var body: some View {
        Group {
            if !viewModel.whisperInstalled {
                DependencyView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $selectedTab) {
                    DictationView()
                        .environmentObject(viewModel)
                        .environmentObject(claudeService)
                        .environmentObject(claudePromptManager)
                        .tabItem {
                            Label("Dictation", systemImage: "mic.fill")
                        }
                        .tag(4)
                    
                    TranscriptionView(
                        consoleOutput: $viewModel.consoleOutput,
                        isProcessing: $viewModel.isProcessing,
                        processingStage: $viewModel.processingStage,
                        processingProgress: $viewModel.processingProgress,
                        claudeService: claudeService,
                        claudePromptManager: claudePromptManager,
                        fileClaudeEnabled: $viewModel.fileClaudeEnabled,
                        fileClaudePromptID: $viewModel.fileClaudePromptID,
                        onDrop: { url, model, format in
                            viewModel.transcribe(url: url, model: model, format: format)
                        },
                        onCancel: {
                            viewModel.cancelTranscription()
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
            }
        }
        .onChange(of: viewModel.whisperInstalled) { oldValue, installed in
            if installed {
                prefetch.refresh()
                prefetch.refreshSizes()
                
                // Only request permissions after a real installation (not just a launch check)
                // Check if we were installing - use a slight delay to catch the flag before it resets
                if viewModel.isInstalling || oldValue == false {
                    // Check if this is a fresh install by looking at UserDefaults
                    let hasPromptedForPermissions = UserDefaults.standard.bool(forKey: "hasPromptedForPermissions")
                    if !hasPromptedForPermissions {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            PermissionsManager.shared.requestAllPermissions()
                            PermissionsManager.shared.promptForAccessibility()
                            UserDefaults.standard.set(true, forKey: "hasPromptedForPermissions")
                        }
                    }
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
            // Just check permissions, don't force prompt
            PermissionsManager.shared.checkPermissions()
        }
        // Sheet removed - using Group/Condition instead
        .navigationTitle("WhisperWrap")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permissions whenever app becomes active (e.g. returning from System Settings)
            PermissionsManager.shared.checkPermissions()
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
