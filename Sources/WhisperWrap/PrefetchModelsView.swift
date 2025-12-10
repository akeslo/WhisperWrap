import SwiftUI

struct PrefetchModelsView: View {
    @EnvironmentObject var prefetch: PrefetchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prefetch Models")
                .font(.title2)
                .fontWeight(.bold)
            Text("Optional: download model weights ahead of time. First use also downloads automatically.")
                .foregroundColor(.secondary)
            HStack {
                Button("Refresh Status") { prefetch.refresh() }
                Button("Open Cache Folder") { prefetch.openCacheFolder() }
                Spacer()
            }

            ForEach(Model.allCases) { model in
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.displayName)
                        if let size = prefetch.sizes[model] {
                            Text(size).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    switch prefetch.statuses[model] ?? .notPrefetched {
                    case .notPrefetched:
                        Button("Prefetch") { prefetch.prefetch(model) }
                    case .fetching:
                        ProgressView().frame(width: 80)
                    case .prefetched:
                        Label("Ready", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                    case .failed(let msg):
                        VStack(alignment: .trailing) {
                            Text("Failed").foregroundColor(.red)
                            Text(msg).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            prefetch.refresh()
            prefetch.refreshSizes()
        }
    }
}
