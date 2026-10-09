import SwiftUI
import AppKit

private struct LastResultView: View {
    let rawTranscription: String
    let processedOutput: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TakeText(title: "Raw", text: rawTranscription, empty: "Nothing dictated yet.")
                if !processedOutput.isEmpty {
                    Divider().overlay(Theme.hairline)
                    TakeText(title: "Refined", text: processedOutput, empty: "")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(Theme.ground)
        .preferredColorScheme(.dark)
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
        window.title = "Last Dictation"
        window.appearance = NSAppearance(named: .darkAqua)
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
