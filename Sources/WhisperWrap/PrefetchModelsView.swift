import SwiftUI

struct PrefetchModelsView: View {
    @EnvironmentObject var prefetch: PrefetchManager

    var body: some View {
        Panel(title: "Whisper models") {
            Text("Download weights ahead of time. A model also downloads on first use.")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
            ForEach(Model.allCases) { model in
                HStack(spacing: 10) {
                    Text(model.displayName).foregroundStyle(Theme.text)
                    if let size = prefetch.sizes[model] {
                        Text(size).font(Theme.numerals(11)).foregroundStyle(Theme.amber)
                    }
                    Spacer()
                    switch prefetch.statuses[model] ?? .notPrefetched {
                    case .notPrefetched:
                        Button("Download") { prefetch.prefetch(model) }
                    case .fetching:
                        TallyLight(color: Theme.amber, pulsing: true)
                        Text("Downloading \(Int((prefetch.progress[model] ?? 0) * 100))%")
                            .font(Theme.numerals(11))
                            .foregroundStyle(Theme.textDim)
                        Button("Cancel") { prefetch.cancelPrefetch(model) }
                    case .prefetched:
                        TallyLight(color: Theme.landed)
                        Text("Ready").foregroundStyle(Theme.textDim)
                    case .failed(let msg):
                        VStack(alignment: .trailing, spacing: 2) {
                            Button("Retry Download") { prefetch.prefetch(model) }
                            Text(msg).font(.caption2).foregroundStyle(Theme.textDim).lineLimit(2)
                        }
                    }
                }
            }
            HStack {
                Button("Refresh Status") { prefetch.refresh() }
                Button("Show Cache Folder") { prefetch.openCacheFolder() }
                Spacer()
            }
        }
        .onAppear {
            prefetch.refresh()
            prefetch.refreshSizes()
        }
    }
}
