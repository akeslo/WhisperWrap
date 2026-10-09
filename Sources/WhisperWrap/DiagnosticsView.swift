import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var viewModel: ContentViewModel

    var body: some View {
        Panel(title: "Diagnostics") {
            SettingRow(label: "Version") {
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                    .font(Theme.numerals(12)).foregroundStyle(Theme.amber)
            }
            SettingRow(label: "Log entries") {
                Text("\(viewModel.logCount)").font(Theme.numerals(12)).foregroundStyle(Theme.amber)
            }
            if viewModel.logCount == 0 {
                Text("No logs yet. Dictate once to generate some.")
                    .font(.caption).foregroundStyle(Theme.textDim)
            } else {
                ScrollView {
                    Text(viewModel.recentLogs)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(height: 140)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack {
                Button("Copy Logs") {
                    let logs = LoggerService.shared.export()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs.isEmpty ? "(no logs captured)" : logs, forType: .string)
                }
                Button("Save Logs to Downloads") { saveLogs() }
                Button("Clear Logs") { LoggerService.shared.clear() }
                Spacer()
                Link("Outsource Wisely", destination: URL(string: "https://www.outsourcewisely.com/")!)
                    .font(.caption)
            }
        }
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
            LoggerService.shared.debug("Failed to save logs: \(error)")
        }
    }
}
