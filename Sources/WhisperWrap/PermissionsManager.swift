import AVFoundation
import AppKit
import Foundation

// MARK: - Types

enum PermissionStatus: Equatable {
    case healthy
    case denied
    case broken        // TCC says allowed but live probe disagrees — toggle off/on in System Settings
    case notDetermined
}

struct HealthCheckResult: Equatable {
    let microphone: PermissionStatus
    let accessibility: PermissionStatus

    // notDetermined is not unhealthy — OS hasn't prompted yet, recording works once granted
    var isHealthy: Bool {
        (microphone == .healthy || microphone == .notDetermined) && accessibility != .broken
    }

    var problems: [String] {
        var result: [String] = []
        switch microphone {
        case .denied:  result.append("Microphone permission denied")
        case .broken:  result.append("Microphone looks enabled but isn't working — toggle it off and on in System Settings")
        default: break
        }
        switch accessibility {
        case .denied:  result.append("Accessibility permission denied")
        case .broken:  result.append("Accessibility looks enabled but isn't working — toggle it off and on in System Settings")
        default: break
        }
        return result
    }
}

// MARK: - PermissionsManager

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var hasMicrophoneAccess: Bool = false
    @Published var hasAccessibilityAccess: Bool = false
    @Published var healthResult: HealthCheckResult? = nil

    private init() {}

    // MARK: - Fast sync check (used for immediate UI updates)

    func checkPermissions() {
        hasMicrophoneAccess = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibilityAccess = AXIsProcessTrusted()
    }

    // MARK: - Full live-probe health check (async, call on startup + app activation)

    @discardableResult
    func runHealthCheck() async -> HealthCheckResult {
        let micStatus = await checkMicrophoneLive()
        let axStatus = checkAccessibilityLive()
        let result = HealthCheckResult(microphone: micStatus, accessibility: axStatus)
        healthResult = result
        // Keep legacy flags in sync
        hasMicrophoneAccess = (micStatus == .healthy || micStatus == .notDetermined)
        hasAccessibilityAccess = (axStatus == .healthy)
        return result
    }

    // MARK: - Microphone live probe

    private func checkMicrophoneLive() async -> PermissionStatus {
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch authStatus {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        case .authorized: break
        @unknown default: return .denied
        }
        let probeSucceeds = await probeMicrophone()
        return probeSucceeds ? .healthy : .broken
    }

    nonisolated private func probeMicrophone() async -> Bool {
        guard AVCaptureDevice.default(for: .audio) != nil else { return false }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func inc() { lock.lock(); n += 1; lock.unlock() }
            func value() -> Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let counter = Counter()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            if buf.frameLength > 0 { counter.inc() }
        }
        do { try engine.start() } catch {
            inputNode.removeTap(onBus: 0)
            return false
        }

        let deadline = Date().addingTimeInterval(0.5)
        while counter.value() == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        engine.stop()
        inputNode.removeTap(onBus: 0)
        return counter.value() > 0
    }

    // MARK: - Accessibility live check

    private func checkAccessibilityLive() -> PermissionStatus {
        guard AXIsProcessTrusted() else { return .denied }
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value)
        let probeOK = (err == .success || err == .noValue)
        return probeOK ? .healthy : .broken
    }

    // MARK: - Permission requests

    func requestAllPermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        checkPermissions()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func isMicrophoneAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func promptForAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        NSApp.activate(ignoringOtherApps: true)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
