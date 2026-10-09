import SwiftUI

/// Live status, start/stop, and the last take with its refined readback.
struct DictationRecordingView: View {
    @ObservedObject var viewModel: DictationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                TallyLight(color: tally.color, pulsing: tally.pulsing)
                Text(tally.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                if viewModel.isRecording {
                    LevelMeter(level: viewModel.audioLevel)
                }
                Spacer()
                controls
            }
            .padding(14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))

            Panel(title: "Last dictation") {
                TakeText(title: "Raw", text: viewModel.lastRawTranscription, empty: "Nothing dictated yet. Press \(viewModel.hotkeyDisplayString) and speak.")
                if !viewModel.lastProcessedOutput.isEmpty {
                    Divider().overlay(Theme.hairline)
                    TakeText(title: "Refined", text: viewModel.lastProcessedOutput, empty: "")
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await viewModel.refineLast() }
                    } label: {
                        Label(viewModel.isRefining ? "Refining…" : "Refine Last", systemImage: "wand.and.stars")
                    }
                    .disabled(viewModel.lastRawTranscription.isEmpty || viewModel.isRefining || viewModel.isRecording)
                }
            }
        }
    }

    private var tally: (color: Color, pulsing: Bool, label: String) {
        if viewModel.isRecording { return (Theme.tx, true, "Recording") }
        if viewModel.isProcessing { return (Theme.amber, true, "Decoding") }
        if viewModel.isRefining { return (Theme.amber, true, "Refining") }
        if !viewModel.lastRawTranscription.isEmpty { return (Theme.landed, false, "Pasted") }
        return (Theme.textDim, false, "Ready")
    }

    @ViewBuilder
    private var controls: some View {
        if viewModel.isRecording {
            Button("Cancel") { viewModel.cancelRecording() }
            Button("Stop Dictation") { viewModel.stopRecording() }
                .keyboardShortcut(.defaultAction)
        } else {
            Button {
                viewModel.startRecording()
            } label: {
                Label("Start Dictation", systemImage: "mic.fill")
            }
            .disabled(viewModel.isProcessing)
        }
    }
}

/// Input level as a short bar row; driven by the real audio level, not random noise.
private struct LevelMeter: View {
    let level: Float
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Float(i) / 12 < level ? Theme.tx : Theme.hairline)
                    .frame(width: 4, height: 14)
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}

struct TakeText: View {
    let title: String
    let text: String
    let empty: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
                .disabled(text.isEmpty)
            }
            Text(text.isEmpty ? empty : text)
                .foregroundStyle(text.isEmpty ? Theme.textDim : Theme.text)
                .textSelection(.enabled)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
