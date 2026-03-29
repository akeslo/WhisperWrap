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

                if state.status != .processingWithClaude && state.status != .selectingPrompt {
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

            if state.status == .selectingPrompt {
                Divider()
                VStack(spacing: 8) {
                    if state.isEnteringCustomPrompt {
                        HStack(spacing: 8) {
                            TextField("Enter custom prompt...", text: $state.customPromptText)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor))
                                .cornerRadius(8)
                                .onSubmit {
                                    HUDWindowController.shared.submitCustomPrompt(state.customPromptText)
                                }
                            Button(action: {
                                state.isEnteringCustomPrompt = false
                            }) {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 6) {
                                ForEach(state.availablePrompts) { prompt in
                                    Button(action: {
                                        HUDWindowController.shared.selectPrompt(prompt)
                                    }) {
                                        Text(prompt.name)
                                            .font(.system(.caption, weight: prompt.id == state.defaultPromptID ? .semibold : .regular))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(prompt.id == state.defaultPromptID ? Color.purple.opacity(0.2) : Color.secondary.opacity(0.1))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(prompt.id == state.defaultPromptID ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button(action: {
                                    HUDWindowController.shared.skipPromptSelection()
                                }) {
                                    Text("None")
                                        .font(.system(.caption))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.secondary.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                                Button(action: {
                                    state.isEnteringCustomPrompt = true
                                }) {
                                    Text("Custom...")
                                        .font(.system(.caption))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.secondary.opacity(0.1))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.trailing, 4)
                        }
                        .scrollIndicators(.visible)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple.opacity(0.4))
                            .frame(width: geo.size.width * state.countdownProgress, height: 4)
                            .animation(.linear(duration: 0.05), value: state.countdownProgress)
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }

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
        case .selectingPrompt: return "brain"
        case .processingWithClaude: return "brain"
        }
    }

    private var hudIconColor: Color {
        switch state.status {
        case .listening: return .red
        case .transcribing: return .orange
        case .selectingPrompt: return .purple
        case .processingWithClaude: return .purple
        }
    }

    private var hudStatusText: String {
        switch state.status {
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .selectingPrompt: return "Select prompt"
        case .processingWithClaude: return "Processing with Claude..."
        }
    }
}
