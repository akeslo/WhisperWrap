import Foundation
import Combine
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class PrefetchManager: ObservableObject {
    @Published var statuses: [Model: Status] = [:]
    @Published var sizes: [Model: String] = [:]

    enum Status: Equatable {
        case notPrefetched
        case fetching
        case prefetched
        case failed(String)
    }

    private let shell = ShellService()
    private let applicationSupportDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperWrap")
    }()

    private lazy var pythonEnv = PythonEnvManager(applicationSupportDirectory: applicationSupportDirectory, shell: shell)

    private var modelsCacheDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("models")
    }

    init() {
        for m in Model.allCases { statuses[m] = .notPrefetched }
        // Create cache dir if needed
        try? FileManager.default.createDirectory(at: modelsCacheDirectory, withIntermediateDirectories: true)
        
        refresh()
        refreshSizes()
    }

    func prefetch(_ model: Model) {
        guard statuses[model] != .fetching else { return }
        statuses[model] = .fetching

        Task {
            let py = pythonEnv.pythonPath.replacingOccurrences(of: "\"", with: "\\\"")
            let cachePath = modelsCacheDirectory.path.replacingOccurrences(of: "\"", with: "\\\"")
            
            // Set HF_HUB_CACHE env var in python
            let script = """
            import os
            os.environ['HF_HUB_CACHE'] = "\(cachePath)"
            from faster_whisper import WhisperModel
            WhisperModel("\(model.fasterWhisperName)", device="auto", compute_type="int8")
            print("OK")
            """
            
            let cmd = "\"\(py)\" -c \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\""
            do {
                let out = try await shell.runCommand(cmd)
                if out.contains("OK") {
                    self.statuses[model] = .prefetched
                } else {
                    self.statuses[model] = .failed(out)
                }
            } catch {
                self.statuses[model] = .failed(String(describing: error))
            }
        }
    }

    func refresh() {
        Task {
            for m in Model.allCases {
                await check(model: m)
            }
        }
    }

    func refreshSizes() {
        Task {
            for m in Model.allCases {
                await fetchSize(for: m)
            }
        }
    }

    func openCacheFolder() {
        Task {
            let path = modelsCacheDirectory.path
            LoggerService.shared.debug("Opening cache path: \(path)")
            
            // Ensure directory exists
            var isDir: ObjCBool = false
            let fm = FileManager.default
            if !fm.fileExists(atPath: path, isDirectory: &isDir) || !isDir.boolValue {
                try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
            #if os(macOS)
            let url = URL(fileURLWithPath: path, isDirectory: true)
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            #endif
        }
    }

    private func check(model: Model) async {
        let py = pythonEnv.pythonPath.replacingOccurrences(of: "\"", with: "\\\"")
        let repo = repoID(for: model)
        let cachePath = modelsCacheDirectory.path.replacingOccurrences(of: "\"", with: "\\\"")
        
        // Check the custom cache directory for models
        let script = """
        import os, sys

        paths_to_check = []

        # Custom Cache
        custom = "\(cachePath)"
        if custom:
            paths_to_check.append(custom)

        repo = sys.argv[1]
        print(f"DEBUG_PY: Checking model repo: {repo}")
        
        if '/' in repo:
            org, name = repo.split('/', 1)
        else:
            org, name = 'models', repo
            
        dir_name = f'models--{org}--{name}'
        
        have = False
        for root in paths_to_check:
            base = os.path.join(root, dir_name)
            print(f"DEBUG_PY: Checking base path: {base}")
            
            if os.path.isdir(base):
                snaps = os.path.join(base, 'snapshots')
                if os.path.isdir(snaps):
                    for h in os.listdir(snaps):
                        sp = os.path.join(snaps, h)
                        if os.path.isdir(sp):
                            # look for a typical file - bin or safetensors + config
                            has_bin = os.path.exists(os.path.join(sp, 'model.bin'))
                            has_safe = os.path.exists(os.path.join(sp, 'model.safetensors'))
                            has_config = os.path.exists(os.path.join(sp, 'config.json'))
                            
                            if (has_bin or has_safe) and has_config:
                                have = True
                                print(f"DEBUG_PY: Found valid model in {root}")
                                break
            if have:
                break
                
        if not have:
            print("DEBUG_PY: No valid model found in any cache.")

        print('HAVE' if have else 'MISS')
        """
        
        let cmd = "\"\(py)\" -c \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" \"\(repo)\""
        do {
            let out = try await shell.runCommand(cmd)
            LoggerService.shared.debug("Check output for \(model.displayName):\n\(out)")
            if out.contains("HAVE") {
                statuses[model] = .prefetched
            } else {
                if statuses[model] != .fetching { statuses[model] = .notPrefetched }
            }
        } catch {
            LoggerService.shared.debug("Check failed for \(model.displayName) with error: \(error)")
            if statuses[model] != .fetching { statuses[model] = .notPrefetched }
        }
    }

    private func repoID(for model: Model) -> String {
        switch model {
        case .tiny: return "Systran/faster-whisper-tiny"
        case .base: return "Systran/faster-whisper-base"
        case .small: return "Systran/faster-whisper-small"
        case .medium: return "Systran/faster-whisper-medium"
        case .large: return "Systran/faster-whisper-large-v3"
        case .turbo: return "Systran/faster-whisper-large-v3-turbo"
        }
    }

    private func fetchSize(for model: Model) async {
        let py = pythonEnv.pythonPath.replacingOccurrences(of: "\"", with: "\\\"")
        let repo = repoID(for: model)
         let cachePath = modelsCacheDirectory.path.replacingOccurrences(of: "\"", with: "\\\"")
         
        let script = """
        import sys, os
        os.environ['HF_HUB_CACHE'] = "\(cachePath)"
        from huggingface_hub import HfApi
        repo = sys.argv[1]
        api = HfApi()
        total = 0
        try:
            info = api.repo_info(repo, repo_type='model', files_metadata=True)
            files = getattr(info, 'siblings', [])
            for f in files:
                size = getattr(f, 'size', None)
                if size:
                    total += int(size)
            print(total)
        except Exception:
            print(0)
        """
        let cmd = "\"\(py)\" -c \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" \"\(repo)\""
        do {
            let out = try await shell.runCommand(cmd).trimmingCharacters(in: .whitespacesAndNewlines)
            if let bytes = Int64(out), bytes > 0 {
                sizes[model] = Self.humanReadable(bytes: bytes)
            }
        } catch {
            // ignore errors here
        }
    }

    private static func humanReadable(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
