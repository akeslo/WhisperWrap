import SwiftUI

/// First-run onboarding in the menu bar popover (ported from MiniWhisper): one "Grant" row per
/// missing permission, polling until the user flips them in System Settings.
struct PermissionsBanner: View {
    @ObservedObject private var permissions = PermissionsManager.shared

    private var mic: PermissionStatus { permissions.healthResult?.microphone ?? .notDetermined }
    private var ax: PermissionStatus { permissions.healthResult?.accessibility ?? .denied }

    var body: some View {
        if mic != .healthy || ax != .healthy {
            VStack(alignment: .leading, spacing: 8) {
                Text("WhisperWrap needs access before it can dictate")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)

                if mic != .healthy {
                    PermissionRow(icon: "mic.slash", label: "Microphone", detail: detail(mic, "Needed to hear you")) {
                        if mic == .notDetermined {
                            PermissionsManager.shared.requestAllPermissions()
                        } else {
                            PermissionsManager.shared.openSystemSettings()
                        }
                    }
                }
                if ax != .healthy {
                    PermissionRow(icon: "keyboard", label: "Accessibility", detail: detail(ax, "Needed to paste into other apps")) {
                        PermissionsManager.shared.promptForAccessibility()
                        PermissionsManager.shared.openAccessibilitySettings()
                    }
                }
            }
            .padding([.horizontal, .top])
            .task {
                // System Settings changes don't notify us; poll while the banner is up.
                while !Task.isCancelled {
                    let result = await PermissionsManager.shared.runHealthCheck()
                    if result.microphone == .healthy && result.accessibility == .healthy { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private func detail(_ status: PermissionStatus, _ fallback: String) -> String {
        status == .broken ? "On but not working: turn it off and on in System Settings" : fallback
    }
}

/// On the very first launch, ask for microphone and Accessibility up front instead of waiting
/// for the first failed dictation.
enum Onboarding {
    private static let key = "hasCompletedOnboarding"

    @MainActor static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        PermissionsManager.shared.requestAllPermissions()
        if !PermissionsManager.shared.isAccessibilityTrusted() {
            PermissionsManager.shared.promptForAccessibility()
        }
        MenuBarManager.shared.openPopover()
    }
}

/// System page: always-visible permission status with a fix action per row.
struct PermissionsPanel: View {
    @ObservedObject private var permissions = PermissionsManager.shared

    var body: some View {
        let mic = permissions.healthResult?.microphone ?? .notDetermined
        let ax = permissions.healthResult?.accessibility ?? .denied
        Panel(title: "Permissions") {
            row("Microphone", mic, ok: "Granted", fix: "Open Settings") {
                if mic == .notDetermined { PermissionsManager.shared.requestAllPermissions() }
                else { PermissionsManager.shared.openSystemSettings() }
            }
            row("Accessibility", ax, ok: "Granted", fix: "Open Settings") {
                PermissionsManager.shared.promptForAccessibility()
                PermissionsManager.shared.openAccessibilitySettings()
            }
        }
        .task { _ = await PermissionsManager.shared.runHealthCheck() }
    }

    private func row(_ label: String, _ status: PermissionStatus, ok: String, fix: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            TallyLight(color: status == .healthy ? Theme.landed : Theme.amber)
            Text(label).foregroundStyle(Theme.text)
            Spacer()
            if status == .healthy {
                Text(ok).foregroundStyle(Theme.textDim)
            } else {
                Text(status == .broken ? "On but not working" : "Not granted").font(.caption).foregroundStyle(Theme.textDim)
                Button(fix, action: action)
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let label: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Theme.amber).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Text("Grant Access").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
