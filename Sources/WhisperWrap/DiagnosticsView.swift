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
                        pasteboard.setString(logs.isEmpty ? "(no logs captured)" : logs, forType: .string)
                    }

                    Button("Save to Downloads") {
                        saveLogs()
                    }

                    Button("Clear") {
                        LoggerService.shared.clear()
                    }

                    Spacer()
                    Text("\(viewModel.logCount) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if viewModel.logCount == 0 {
                    Text("No logs captured yet. Start a recording to generate logs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        Text(viewModel.recentLogs)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 120)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(4)
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
        let content = logs.isEmpty ? "(no logs captured)" : logs
        let filename = "WhisperWrap_Logs_\(Int(Date().timeIntervalSince1970)).txt"
        let tempUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try content.write(to: tempUrl, atomically: true, encoding: .utf8)

            if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let destUrl = downloads.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: destUrl)
                try FileManager.default.moveItem(at: tempUrl, to: destUrl)
                NSWorkspace.shared.activateFileViewerSelecting([destUrl])
            }
        } catch {
            print("Failed to save logs: \(error)")
        }
    }
}
