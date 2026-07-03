import SwiftUI
import AppKit

private struct LastResultView: View {
    let rawTranscription: String
    let processedOutput: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section(title: "Transcription", text: rawTranscription)
                if !processedOutput.isEmpty {
                    Divider()
                    section(title: "AI Output", text: processedOutput)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder
    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .disabled(text.isEmpty)
            }
            Text(text.isEmpty ? "No transcription yet." : text)
                .font(.system(.body, design: .default))
                .foregroundColor(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
class LastResultWindowController: NSWindowController {
    static let shared = LastResultWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Last Transcription"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(rawTranscription: String, processedOutput: String) {
        window?.contentView = NSHostingView(
            rootView: LastResultView(rawTranscription: rawTranscription, processedOutput: processedOutput)
        )
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
