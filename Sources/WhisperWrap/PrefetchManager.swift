import Foundation
import SwiftUI
import WhisperKit

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

    // WhisperKit stores CoreML models under Application Support
    private let modelCacheBase: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }()

    init() {
        for m in Model.allCases { statuses[m] = .notPrefetched }
        refresh()
        refreshSizes()
    }

    func prefetch(_ model: Model) {
        guard statuses[model] != .fetching else { return }
        statuses[model] = .fetching
        Task {
            do {
                _ = try await WhisperKit.download(variant: model.whisperKitModelName)
                statuses[model] = .prefetched
                await fetchSize(for: model)
            } catch {
                statuses[model] = .failed(error.localizedDescription)
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
        let url = modelCacheBase
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func check(model: Model) async {
        guard statuses[model] != .fetching else { return }
        let modelDir = modelCacheBase.appendingPathComponent(model.whisperKitModelName)
        // Mere directory existence doesn't distinguish a completed download from one
        // interrupted mid-fetch (WhisperKit creates the directory before it's fully
        // populated) — require at least one non-empty file inside before calling it
        // prefetched, so an interrupted download reads as notPrefetched instead of
        // silently masquerading as a finished one (R12).
        let hasContent = directorySize(at: modelDir) > 0
        statuses[model] = hasContent ? .prefetched : .notPrefetched
    }

    private func fetchSize(for model: Model) async {
        let modelDir = modelCacheBase.appendingPathComponent(model.whisperKitModelName)
        let bytes = directorySize(at: modelDir)
        if bytes > 0 {
            sizes[model] = Self.humanReadable(bytes: Int64(bytes))
        }
    }

    private func directorySize(at url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += size
        }
        return total
    }

    private static func humanReadable(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
