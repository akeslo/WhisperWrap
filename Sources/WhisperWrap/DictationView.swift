import SwiftUI

struct DictationView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    @EnvironmentObject var claudePromptManager: ClaudePromptManager

    var body: some View {
        Page(title: "Dictate", lede: "Hotkey, speak, and it's pasted. ⌥⌘R refines it in place.") {
            DictationRecordingView(viewModel: viewModel)
            DictationSettingsView(viewModel: viewModel, claudePromptManager: claudePromptManager)
        }
        .onAppear { viewModel.contentViewModel = contentViewModel }
    }
}
