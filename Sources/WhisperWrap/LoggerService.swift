import Foundation
import Combine

@MainActor
final class LoggerService: ObservableObject {
    static let shared = LoggerService()
    
    @Published private(set) var logs: [String] = []
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    private init() {}
    
    nonisolated func debug(_ message: String) {
        Task { @MainActor in
            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "[\(timestamp)] \(message)"
            self.logs.append(logEntry)
            
            if self.logs.count > 5000 {
                self.logs.removeFirst(self.logs.count - 5000)
            }
        }
    }
    
    func export() -> String {
        return logs.joined(separator: "\n")
    }
    
    func clear() {
        logs.removeAll()
    }
}
