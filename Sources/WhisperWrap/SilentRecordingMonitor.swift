import Foundation

enum SilentRecordingEvent: Equatable {
    case started(silenceSince: Date)
    case recovered
}

/// Pure state machine: detects when the mic has been continuously silent
/// for `debounceSeconds`. Hysteresis: mid-zone readings keep the timer
/// running but don't trigger; only actual speech (>= speechThreshold) resets.
struct SilentRecordingMonitor {
    let silenceThresholdDBFS: Double   // dBFS at or below = silence (default -60)
    let speechThresholdDBFS: Double    // dBFS at or above = confirmed speech (default -50)
    let debounceSeconds: TimeInterval  // default 90s

    private var episode: Episode?

    private struct Episode {
        var silenceSince: Date
        var fired: Bool
    }

    init(
        silenceThresholdDBFS: Double = -60,
        speechThresholdDBFS: Double = -50,
        debounceSeconds: TimeInterval = 90
    ) {
        self.silenceThresholdDBFS = silenceThresholdDBFS
        self.speechThresholdDBFS = speechThresholdDBFS
        self.debounceSeconds = debounceSeconds
    }

    mutating func update(micDBFS: Double, now: Date = Date()) -> SilentRecordingEvent? {
        let silent = micDBFS <= silenceThresholdDBFS
        let speech = micDBFS >= speechThresholdDBFS

        if silent {
            return handleSilent(now: now)
        }
        if speech {
            return clearEpisode()
        }
        // Mid-zone: keep debounce timer running, no event
        return nil
    }

    mutating func reset() {
        episode = nil
    }

    private mutating func handleSilent(now: Date) -> SilentRecordingEvent? {
        guard var ep = episode else {
            episode = Episode(silenceSince: now, fired: false)
            return nil
        }
        if ep.fired { return nil }
        if now.timeIntervalSince(ep.silenceSince) >= debounceSeconds {
            ep.fired = true
            episode = ep
            return .started(silenceSince: ep.silenceSince)
        }
        return nil
    }

    private mutating func clearEpisode() -> SilentRecordingEvent? {
        guard let ep = episode else { return nil }
        episode = nil
        return ep.fired ? .recovered : nil
    }
}
