import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var viewModel: ContentViewModel

    @State private var pythonInfo: String = ""
    @State private var fwInfo: String = ""

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
                Label("Venv Path", systemImage: "folder")
                Text(viewModel.embeddedVenvPath)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Group {
                Label("Python Version", systemImage: "terminal")
                Text(pythonInfo.isEmpty ? "Checking..." : pythonInfo)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Label("faster-whisper Status", systemImage: "checkmark.circle")
                Text(fwInfo.isEmpty ? "Checking..." : fwInfo)
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
        .onAppear { runPythonInfo(); runFWInfo() }
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
                try? FileManager.default.removeItem(at: destUrl) // overload if exists
                try FileManager.default.moveItem(at: tempUrl, to: destUrl)
                
                // Show in Finder
                NSWorkspace.shared.activateFileViewerSelecting([destUrl])
            }
        } catch {
            print("Failed to save logs: \(error)")
        }
    }

    private func runPythonInfo() {
        Task {
            let py = viewModel.embeddedPythonPath.replacingOccurrences(of: "\"", with: "\\\"")
            let cmd = "\"\(py)\" -V 2>&1 || python3 -V 2>&1"
            let out = (try? await viewModel.runShell(cmd)) ?? "(error)"
            pythonInfo = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func runFWInfo() {
        Task {
            let py = viewModel.embeddedPythonPath.replacingOccurrences(of: "\"", with: "\\\"")
            let cmd = "\"\(py)\" -c \"import faster_whisper,ctranslate2; print('FW', faster_whisper.__version__); print('CT2', ctranslate2.__version__)\""
            let out = (try? await viewModel.runShell(cmd)) ?? "(error)"
            fwInfo = out.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: ", ")
        }
    }
}
