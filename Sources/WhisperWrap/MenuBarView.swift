import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WhisperWrap")
                    .font(.headline)
                
                Spacer()
                
                Button(action: openMainApp) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Settings")
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Quick Actions
            VStack(spacing: 12) {
                // Recording Control Button
                Button(action: {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                    // Popover is now closed by MenuBarManager when recording state changes
                }) {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.fill")
                        Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                        Spacer()
                        Text("⌥Space")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(viewModel.isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Show Last Transcription
                if !viewModel.isRecording && !viewModel.transcribedText.isEmpty {
                    Button(action: {
                        contentViewModel.requestedTab = 4 // Dictation tab
                        openMainApp()
                    }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                            Text("Show Last Transcription")
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                // TTS Button
                Button(action: {
                    contentViewModel.requestedTab = 3 // TTS tab
                    openMainApp()
                }) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Text to Speech")
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Audio to Text Button
                Button(action: {
                    contentViewModel.requestedTab = 0 // Transcribe tab
                    openMainApp()
                }) {
                    HStack {
                        Image(systemName: "waveform")
                        Text("Transcribe")
                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Quit Button
            Button(action: {
                NSApp.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit WhisperWrap")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .frame(width: 300)
        .onAppear {
            viewModel.contentViewModel = contentViewModel
        }
        .alert(item: $viewModel.activeAlert) { alertType in
            switch alertType {
            case .accessibility:
                return Alert(
                    title: Text("Accessibility Access Required"),
                    message: Text("Auto-paste requires accessibility permissions. The transcribed text has been copied to your clipboard, but cannot be pasted automatically. Please enable accessibility access in System Settings to use auto-paste."),
                    primaryButton: .default(Text("Open Settings"), action: {
                        PermissionsManager.shared.openAccessibilitySettings()
                        MenuBarManager.shared.closePopover()
                    }),
                    secondaryButton: .cancel()
                )
            case .microphoneDenied:
                return Alert(
                    title: Text("Microphone Access Denied"),
                    message: Text("WhisperWrap needs microphone access to dictate text. Please enable it in System Settings."),
                    primaryButton: .default(Text("Open Settings"), action: {
                        PermissionsManager.shared.openSystemSettings()
                        MenuBarManager.shared.closePopover()
                    }),
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    private func openMainApp() {
        // Signal AppDelegate to allow window to show
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.shouldShowMainWindow = true
        }
        
        // First, try to find and focus an existing main window
        for window in NSApp.windows {
            if window.identifier?.rawValue == "main" || window.title.contains("WhisperWrap") {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        
        // Only open a new window if none exists
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
