import SwiftUI

/// Main-window sidebar destinations.
enum SidebarPage: String, CaseIterable, Identifiable {
    case dictate, files, voice, prompts, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .files: "Files"
        case .voice: "Voice"
        case .prompts: "Prompts"
        case .system: "System"
        }
    }

    var symbol: String {
        switch self {
        case .dictate: "mic"
        case .files: "waveform"
        case .voice: "speaker.wave.2"
        case .prompts: "text.quote"
        case .system: "gearshape"
        }
    }

    init(tab: WhisperWrapTab) {
        switch tab {
        case .dictation: self = .dictate
        case .transcribe: self = .files
        case .tts: self = .voice
        case .models, .diagnostics: self = .system
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    @EnvironmentObject var claudeService: ClaudeService
    @EnvironmentObject var claudePromptManager: ClaudePromptManager

    init(viewModel: ContentViewModel = ContentViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    @StateObject private var prefetch = PrefetchManager()
    @StateObject private var ttsViewModel = TTSViewModel()
    @State private var page: SidebarPage? = .dictate

    var body: some View {
        NavigationSplitView {
            List(SidebarPage.allCases, selection: $page) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ground)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.text)
        .onChange(of: viewModel.requestedTab) { _, newTab in
            if let tab = newTab {
                page = SidebarPage(tab: tab)
                viewModel.requestedTab = nil
            }
        }
        .onAppear {
            if let tab = viewModel.requestedTab {
                page = SidebarPage(tab: tab)
                viewModel.requestedTab = nil
            }
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
            PermissionsManager.shared.checkPermissions()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page ?? .dictate {
        case .dictate:
            DictationView()
                .environmentObject(viewModel)
        case .files:
            TranscriptionView(
                consoleOutput: $viewModel.consoleOutput,
                isProcessing: $viewModel.isProcessing,
                processingStage: $viewModel.processingStage,
                processingProgress: $viewModel.processingProgress,
                claudeService: claudeService,
                claudePromptManager: claudePromptManager,
                fileClaudeEnabled: $viewModel.fileClaudeEnabled,
                fileClaudePromptID: $viewModel.fileClaudePromptID,
                onDrop: { url, model, format, useClaude in
                    viewModel.transcribe(url: url, model: model, format: format, useClaude: useClaude)
                },
                onCancel: { viewModel.cancelTranscription() }
            )
        case .voice:
            TTSView(viewModel: ttsViewModel)
        case .prompts:
            PromptsView(claudeService: claudeService, claudePromptManager: claudePromptManager)
        case .system:
            Page(title: "System", lede: "Permissions, speech models, and logs.") {
                PermissionsPanel()
                PrefetchModelsView()
                DiagnosticsView()
            }
            .environmentObject(viewModel)
            .environmentObject(prefetch)
        }
    }
}
