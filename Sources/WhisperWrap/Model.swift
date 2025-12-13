import Foundation

enum Model: String, CaseIterable, Identifiable {
    case tiny, base, small, medium, large, turbo

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .turbo:
            return "Turbo (large-v3-turbo)"
        default:
            return self.rawValue.capitalized
        }
    }

    var fasterWhisperName: String {
        switch self {
        case .turbo:
            return "large-v3-turbo"
        default:
            return self.rawValue
        }
    }
}

