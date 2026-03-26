import SwiftUI

struct HUDView: View {
    @ObservedObject var state: HUDState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: hudIcon)
                    .font(.title2)
                    .foregroundColor(hudIconColor)
                    .symbolEffect(.pulse, isActive: state.status == .listening)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WhisperWrap")
                        .font(.headline)
                        .fixedSize()
                    Text(hudStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize()
                }

                Spacer()

                if state.status != .processingWithClaude {
                    // Visualizer - organic "dancing" bars
                    HStack(spacing: 4) {
                        ForEach(0..<20) { index in
                            let t = state.phase
                            let i = Double(index)
                            let h1 = sin(t + i * 0.6)
                            let h2 = cos(t * 0.8 - i * 1.2)
                            let h3 = sin(t * 0.2 + i * 2.5)
                            let baseSignal = abs(h1 + h2 + 0.5 * h3)
                            let wave = CGFloat(baseSignal) * 12.0

                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.blue)
                                .frame(width: 4, height: 4 + wave * (0.5 + CGFloat(state.audioLevel) * 5.0) + (CGFloat(state.audioLevel) * 30))
                        }
                    }
                    .frame(height: 40)
                    .animation(.linear(duration: 0.05), value: state.phase)
                }

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(state.status == .listening ? "Stop Recording" : "Cancel")
            }
            .padding()

            if state.status == .processingWithClaude && !state.streamingText.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(state.streamingText)
                            .font(.system(.body, design: .default))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                            .id("streamBottom")
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: state.streamingText) { _, _ in
                        withAnimation {
                            proxy.scrollTo("streamBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(10)
    }

    private var hudIcon: String {
        switch state.status {
        case .listening: return "mic.fill"
        case .transcribing: return "waveform.circle.fill"
        case .processingWithClaude: return "brain"
        }
    }

    private var hudIconColor: Color {
        switch state.status {
        case .listening: return .red
        case .transcribing: return .orange
        case .processingWithClaude: return .purple
        }
    }

    private var hudStatusText: String {
        switch state.status {
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processingWithClaude: return "Processing with Claude..."
        }
    }
}
