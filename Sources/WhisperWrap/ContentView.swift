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
            // Request permissions on first launch
            let hasPromptedForPermissions = UserDefaults.standard.bool(forKey: "hasPromptedForPermissions")
            if !hasPromptedForPermissions {
                PermissionsManager.shared.requestAllPermissions()
                PermissionsManager.shared.promptForAccessibility()
                UserDefaults.standard.set(true, forKey: "hasPromptedForPermissions")
            }
            PermissionsManager.shared.checkPermissions()
            prefetch.refresh()
            prefetch.refreshSizes()
        }
        .navigationTitle("WhisperWrap")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Re-check permissions whenever app becomes active (e.g. returning from System Settings)
            PermissionsManager.shared.checkPermissions()
        }
    }
}
