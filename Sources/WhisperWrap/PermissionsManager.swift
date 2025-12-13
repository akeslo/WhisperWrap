import Foundation
import AVFoundation
import AppKit

@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    
    @Published var hasMicrophoneAccess: Bool = false
    @Published var hasAccessibilityAccess: Bool = false

    private init() {}
    
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
    
    func requestAllPermissions() {
        requestMicrophoneAccess()
        // Do NOT force prompt for accessibility on every request, just check status
        // Only prompt if explicitly asked or during a specific setup flow
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
        }
    }
    
    func promptForAccessibility() {
        // Only prompt if not already trusted
        if AXIsProcessTrusted() {
            print("Accessibility already granted, skipping prompt")
            return
        }

        // Activate the app to ensure the dialog appears on top
        NSApp.activate(ignoringOtherApps: true)

        // kAXTrustedCheckOptionPrompt is a global variable. Using literal to avoid concurrency issues.
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        print("Accessibility prompt triggered, trusted: \(isTrusted)")
    }
    
    func isMicrophoneAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }
}
