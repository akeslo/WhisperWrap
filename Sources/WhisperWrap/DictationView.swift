import SwiftUI
import ServiceManagement

struct DictationView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    @EnvironmentObject var claudeService: ClaudeService
    @EnvironmentObject var claudePromptManager: ClaudePromptManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DictationSettingsView(viewModel: viewModel, claudeService: claudeService, claudePromptManager: claudePromptManager)
                DictationRecordingView(viewModel: viewModel)
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            viewModel.contentViewModel = contentViewModel
        }
    }
}
