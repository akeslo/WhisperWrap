import SwiftUI
import ServiceManagement

struct DictationView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            DictationSettingsView(viewModel: viewModel)
            DictationRecordingView(viewModel: viewModel)
        }
        .padding(.vertical)
        .onAppear {
            viewModel.contentViewModel = contentViewModel
        }
    }
}
