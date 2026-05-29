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

    var whisperKitModelName: String {
        switch self {
        case .tiny:   return "openai_whisper-tiny"
        case .base:   return "openai_whisper-base"
        case .small:  return "openai_whisper-small"
        case .medium: return "openai_whisper-medium"
        case .large:  return "openai_whisper-large-v3"
        case .turbo:  return "openai_whisper-large-v3-v20240930_turbo"
        }
    }
}

