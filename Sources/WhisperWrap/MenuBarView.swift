import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TallyLight(color: tally.color, pulsing: tally.pulsing)
                Text(tally.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                KeyCap(keys: viewModel.hotkeyDisplayString)
            }
            .padding(12)

            PermissionsBanner()

            Text(preview)
                .font(.system(size: 12))
                .foregroundStyle(viewModel.lastRawTranscription.isEmpty ? Theme.textDim : Theme.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
                .padding(.horizontal, 12)
                .padding(.top, 4)

            VStack(spacing: 8) {
                Button(action: toggleDictation) {
                    Label(primaryTitle, systemImage: viewModel.isRecording ? "stop.fill" : (viewModel.isProcessing ? "xmark" : "mic.fill"))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .tint(Theme.tx)

                Button {
                    Task { await viewModel.refineLast() }
                } label: {
                    Label(viewModel.isRefining ? "Refining…" : "Refine Last", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(viewModel.lastRawTranscription.isEmpty || viewModel.isRefining || viewModel.isRecording)
            }
            .padding(12)

            Divider().overlay(Theme.hairline)

            HStack {
                Button("Open WhisperWrap") { openMainApp() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textDim)
            .padding(12)
        }
        .background(Theme.ground)
        .preferredColorScheme(.dark)
        .frame(width: 300)
        .onAppear {
            viewModel.contentViewModel = contentViewModel
        }
        .alert(item: $viewModel.activeAlert) { alertType in
            switch alertType {
            case .accessibility:
                return Alert(
                    title: Text("Paste Blocked"),
                    message: Text("Your text is on the clipboard but could not be pasted. Turn on WhisperWrap in System Settings > Privacy & Security > Accessibility, then dictate again."),
                    primaryButton: .default(Text("Open Settings"), action: {
                        PermissionsManager.shared.openAccessibilitySettings()
                        MenuBarManager.shared.closePopover()
                    }),
                    secondaryButton: .cancel()
                )
            case .microphoneDenied:
                return Alert(
                    title: Text("Microphone Blocked"),
                    message: Text("WhisperWrap can't hear you. Turn on WhisperWrap in System Settings > Privacy & Security > Microphone."),
                    primaryButton: .default(Text("Open Settings"), action: {
                        PermissionsManager.shared.openSystemSettings()
                        MenuBarManager.shared.closePopover()
                    }),
                    secondaryButton: .cancel()
                )
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

    private var preview: String {
        let refined = viewModel.lastProcessedOutput
        let raw = viewModel.lastRawTranscription
        if !refined.isEmpty { return refined }
        return raw.isEmpty ? "Press \(viewModel.hotkeyDisplayString) and speak. Your words paste where the cursor is." : raw
    }

    private var primaryTitle: String {
        if viewModel.isRecording { return "Stop Dictation" }
        if viewModel.isProcessing { return "Cancel Transcription" }
        return "Start Dictation"
    }

    private func toggleDictation() {
        if viewModel.isRecording {
            viewModel.stopRecording()
        } else if viewModel.isProcessing {
            // A transcription is in flight against the fixed dictation.wav; starting a new
            // recording would truncate the file it is still reading.
            viewModel.cancelTranscription()
        } else {
            viewModel.startRecording()
        }
    }

    private func openMainApp() {
        // Signal AppDelegate to allow window to show
        if let appDelegate = AppDelegate.shared {
            appDelegate.shouldShowMainWindow = true
        }
        
        // An accessory app can't take focus, so the window opened behind whatever app was
        // frontmost. Become a regular app first, then force the window to the front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title.contains("WhisperWrap") }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openWindow(id: "main")
        }
    }
}
