import Foundation
import AVFoundation
import AppKit

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    
    @Published var hasMicrophoneAccess: Bool = false
    @Published var hasAccessibilityAccess: Bool = false
    @Published var showMicrophoneDeniedAlert: Bool = false
    
    private init() {}
    
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func requestAllPermissions() {
        requestMicrophoneAccess()
        requestAccessibilityAccess()
        checkPermissions()
    }
    
    func checkPermissions() {
        hasMicrophoneAccess = isMicrophoneAuthorized()
        hasAccessibilityAccess = isAccessibilityTrusted()
        print("Permissions check: Mic=\(hasMicrophoneAccess), Access=\(hasAccessibilityAccess)")
    }
    
    private func requestMicrophoneAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone permission granted: \(granted)")
            }
        } else if status == .denied {
            print("Microphone permission denied previously.")
            showMicrophoneDeniedAlert = true
        }
    }
    
    private func requestAccessibilityAccess() {
        // kAXTrustedCheckOptionPrompt is a global variable. Using literal to avoid concurrency issues.
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        print("Accessibility permission trusted: \(isTrusted)")
    }
    
    func isMicrophoneAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
}
