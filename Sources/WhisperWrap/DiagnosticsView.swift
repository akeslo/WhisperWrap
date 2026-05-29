import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var viewModel: ContentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics").font(.title2).fontWeight(.bold)

            Group {
                Label("App Version", systemImage: "info.circle")
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Group {
                Label("Speech Engine", systemImage: "waveform")
                Text("WhisperKit (CoreML / Apple Neural Engine) — no setup required")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            Group {
                Text("Debug Logs").font(.headline)
                HStack {
                    Button("Copy to Clipboard") {
                        let logs = LoggerService.shared.export()
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(logs, forType: .string)
                    }

                    Button("Save to Downloads") {
                        saveLogs()
                    }

                    Button("Clear") {
                        LoggerService.shared.clear()
                    }
                }
            }

            Spacer()

            Link("Made by Outsource Wisely", destination: URL(string: "https://www.outsourcewisely.com/")!)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom)
        }
        .padding()
    }

    private func saveLogs() {
        let logs = LoggerService.shared.export()
        let filename = "WhisperWrap_Logs_\(Int(Date().timeIntervalSince1970)).txt"
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try logs.write(to: tempUrl, atomically: true, encoding: .utf8)

            // Move to Downloads
            if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let destUrl = downloads.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: destUrl) // overwrite if exists
                try FileManager.default.moveItem(at: tempUrl, to: destUrl)

                // Show in Finder
                NSWorkspace.shared.activateFileViewerSelecting([destUrl])
            }
        } catch {
            print("Failed to save logs: \(error)")
        }
    }
}
