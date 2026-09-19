import XCTest
@testable import WhisperWrap

/// A-TEST-1 (REMEDIATION_PLAN.md): SilentRecordingMonitor is a pure state machine the audit
/// flagged as the highest-ROI untested code in the app — it decides when to warn the user
/// their mic has gone dead mid-dictation. These tests exercise its hysteresis directly
/// (silence/mid-zone/speech transitions, debounce timing, fired-once behavior, reset) so a
/// future change to the threshold or debounce logic can't silently break the warning without
/// a test failing.
final class SilentRecordingMonitorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testNoEventBeforeDebounceElapses() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        XCTAssertNil(monitor.update(micDBFS: -70, now: base))
        XCTAssertNil(monitor.update(micDBFS: -70, now: base.addingTimeInterval(89)))
    }

    func testFiresOnceDebounceElapses() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        XCTAssertNil(monitor.update(micDBFS: -70, now: base))
        let event = monitor.update(micDBFS: -70, now: base.addingTimeInterval(90))
        XCTAssertEqual(event, .started(silenceSince: base))
    }

    func testDoesNotRefireWhileStillSilentAfterFiring() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        _ = monitor.update(micDBFS: -70, now: base)
        _ = monitor.update(micDBFS: -70, now: base.addingTimeInterval(90))
        XCTAssertNil(monitor.update(micDBFS: -70, now: base.addingTimeInterval(200)))
    }

    func testMidZoneReadingsKeepTimerRunningWithoutFiringOrResetting() {
        var monitor = SilentRecordingMonitor(silenceThresholdDBFS: -60, speechThresholdDBFS: -50, debounceSeconds: 90)
        XCTAssertNil(monitor.update(micDBFS: -70, now: base))
        // Mid-zone (-55 is between -60 silence and -50 speech): must not reset the episode.
        XCTAssertNil(monitor.update(micDBFS: -55, now: base.addingTimeInterval(45)))
        // Debounce measured from the original silence onset, not reset by the mid-zone sample.
        let event = monitor.update(micDBFS: -70, now: base.addingTimeInterval(90))
        XCTAssertEqual(event, .started(silenceSince: base))
    }

    func testSpeechClearsEpisodeBeforeFiring() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        XCTAssertNil(monitor.update(micDBFS: -70, now: base))
        XCTAssertNil(monitor.update(micDBFS: -40, now: base.addingTimeInterval(10)))
        // Silence timer restarted from scratch: not enough elapsed since the new onset.
        XCTAssertNil(monitor.update(micDBFS: -70, now: base.addingTimeInterval(50)))
    }

    func testSpeechAfterFiringEmitsRecovered() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        _ = monitor.update(micDBFS: -70, now: base)
        _ = monitor.update(micDBFS: -70, now: base.addingTimeInterval(90))
        let event = monitor.update(micDBFS: -40, now: base.addingTimeInterval(95))
        XCTAssertEqual(event, .recovered)
    }

    func testSpeechBeforeFiringEmitsNoRecoveredEvent() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        _ = monitor.update(micDBFS: -70, now: base)
        let event = monitor.update(micDBFS: -40, now: base.addingTimeInterval(10))
        XCTAssertNil(event)
    }

    func testResetClearsEpisodeEvenAfterFiring() {
        var monitor = SilentRecordingMonitor(debounceSeconds: 90)
        _ = monitor.update(micDBFS: -70, now: base)
        _ = monitor.update(micDBFS: -70, now: base.addingTimeInterval(90))
        monitor.reset()
        // Starting fresh: needs a full new debounce window before firing again.
        XCTAssertNil(monitor.update(micDBFS: -70, now: base.addingTimeInterval(91)))
        let event = monitor.update(micDBFS: -70, now: base.addingTimeInterval(91 + 90))
        XCTAssertEqual(event, .started(silenceSince: base.addingTimeInterval(91)))
    }
}
