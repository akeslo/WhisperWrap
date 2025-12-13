import SwiftUI
import ServiceManagement

struct DictationView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel

    var body: some View {
        VStack(spacing: 16) {
            DictationSettingsView(viewModel: viewModel)
            DictationRecordingView(viewModel: viewModel)
        }
        .padding(.vertical, 8)
        .onAppear {
            viewModel.contentViewModel = contentViewModel
        }
    }
}
