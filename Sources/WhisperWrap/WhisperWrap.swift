// The Swift Programming Language
// https://docs.swift.org/swift-book

import Combine
import SwiftUI
import AppKit
import UserNotifications
import Sparkle

final class WWNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = WWNotificationDelegate()

    // Allow notifications to show while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Handle "Stop Recording" action tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "WW_STOP_RECORDING" {
            Task { @MainActor in
                if let delegate = AppDelegate.shared {
                    delegate.dictationViewModel.stopRecording()
                }
            }
        }
        completionHandler()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApp.delegate` is SwiftUI's adaptor proxy, not this class, so `as? AppDelegate`
    /// casts fail. Reach the instance through here instead.
    static private(set) weak var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }
    // Move ownership of ViewModels here to ensure they exist at launch
    var contentViewModel = ContentViewModel()
    var dictationViewModel = DictationViewModel()
    let claudeService = ClaudeService()
    let claudePromptManager = ClaudePromptManager()
    /// nil under `swift run` (no bundle → no Info.plist feed/key for Sparkle).
    private(set) var updaterController: SPUStandardUpdaterController?
    
    // Flag to control whether the main window should be shown
    var shouldShowMainWindow = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Connect dependencies
        dictationViewModel.contentViewModel = contentViewModel
        dictationViewModel.claudeService = claudeService
        dictationViewModel.claudePromptManager = claudePromptManager
        contentViewModel.claudeService = claudeService
        contentViewModel.claudePromptManager = claudePromptManager
        dictationViewModel.prewarmModel()

        if Bundle.main.bundleIdentifier != nil {
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }

        // Notification setup — UNUserNotificationCenter requires a proper .app bundle;
        // skip when running via `swift run` (no bundle ID).
        if Bundle.main.bundleIdentifier != nil {
            let notifCenter = UNUserNotificationCenter.current()
            notifCenter.delegate = WWNotificationDelegate.shared
            let stopAction = UNNotificationAction(
                identifier: "WW_STOP_RECORDING",
                title: "Stop Recording",
                options: [.foreground]
            )
            let silentCategory = UNNotificationCategory(
                identifier: "WW_SILENT_MIC",
                actions: [stopAction],
                intentIdentifiers: [],
                options: []
            )
            notifCenter.setNotificationCategories([silentCategory])
            notifCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        // Setup Menu Bar immediately on launch
        MenuBarManager.shared.setup(dictationViewModel: dictationViewModel, contentViewModel: contentViewModel)

        // Run permission health check on startup
        Task { await PermissionsManager.shared.runHealthCheck() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Onboarding.runIfNeeded() }

        // Check if app is in ~/Applications
        checkAppLocation()
        
        // Observe window notifications to show/hide dock icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeVisible),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkWindowsVisible),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        
        // Stay hidden at launch unless manually opened
        logToFile("Startup: staying hidden")

        // Force close check on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !self.shouldShowMainWindow {
                NSApp.windows.forEach { window in
                    if window.identifier?.rawValue == "main" {
                        window.close()
                    }
                }
            }
        }
    }
    
    func logToFile(_ text: String) {
        LoggerService.shared.debug(text)
    }

    // MARK: - App Location Check

    private func checkAppLocation() {
        let bundleURL = Bundle.main.bundleURL
        if AppMover.isInApplicationsFolder(bundleURL) { return }

        // Development builds from swift build / Xcode.
        let bundlePath = bundleURL.path
        if bundlePath.contains(".build/") || bundlePath.contains("DerivedData") { return }

        // A translocated or disk-image copy can't update itself, so always offer the move there.
        let mustMove = AppMover.isTranslocated(bundleURL) || AppMover.isOnMountedVolume(bundleURL)
        if !mustMove && UserDefaults.standard.bool(forKey: "dismissedAppLocationPrompt") { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showMoveToApplicationsAlert(allowDontAsk: !mustMove)
        }
    }

    private func showMoveToApplicationsAlert(allowDontAsk: Bool) {
        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "WhisperWrap needs to be in your Applications folder to keep permissions and install updates.\n\nIf moving fails, quit WhisperWrap and drag it into Applications in Finder."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        if allowDontAsk { alert.addButton(withTitle: "Don't Ask Again") }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            moveToApplicationsFolder()
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: "dismissedAppLocationPrompt")
        default:
            break
        }
    }

    private func moveToApplicationsFolder() {
        let running = Bundle.main.bundleURL
        // Copy from the real download location, not the read-only translocation mount.
        let original = AppMover.isTranslocated(running) ? AppMover.originalURL(forTranslocated: running) : running
        let source = original ?? running
        let appsDir = URL(fileURLWithPath: "/Applications")
        logToFile("Move: running=\(running.path) source=\(source.path)")

        let destination: URL
        do {
            if FileManager.default.isWritableFile(atPath: appsDir.path) {
                destination = try AppMover.install(from: source, into: appsDir)
            } else {
                destination = try AppMover.installWithAdminPrivileges(from: source, into: appsDir)
            }
        } catch {
            logToFile("Move: FAILED: \(error)")
            showMoveError("\(error.localizedDescription)\n\nQuit WhisperWrap and drag it into the Applications folder in Finder instead.")
            return
        }
        logToFile("Move: installed and verified at \(destination.path)")

        // Remove the downloaded copy only when we know its real path and it isn't on a disk image.
        let leftover = (original != nil && !AppMover.isOnMountedVolume(source)) ? source.path : ""
        // Wait for this process to exit, then open the verified copy, then clean up.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"; [ -n \"$3\" ] && rm -rf \"$3\"; exit 0",
            "_", String(ProcessInfo.processInfo.processIdentifier), destination.path, leftover,
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            logToFile("Move: FAILED to launch relaunch helper: \(error)")
            showMoveError("WhisperWrap was copied to Applications but couldn't relaunch. Quit it and open WhisperWrap from Applications.")
        }
    }

    private func showMoveError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Move Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor @objc private func windowDidBecomeVisible(_ notification: Notification) {
        // Ignore panels (like HUD)
        if let window = notification.object as? NSWindow, window.isKind(of: NSPanel.self) {
            return
        }
        
        logToFile("Window became visible: \(String(describing: notification.object as? NSWindow))")

        // Suppress window unless explicitly requested
        if !shouldShowMainWindow {
            if let window = notification.object as? NSWindow {
                window.close()
            }
            return
        }
        
        // Flag remains true for session to allow window interaction
        
        // Show dock icon when a window becomes visible
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor @objc private func checkWindowsVisible(_ notification: Notification) {
        let closingWindow = notification.object as? NSWindow
        
        // Delay check to allow window to fully close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let visibleWindows = NSApp.windows.filter { 
                $0.isVisible && 
                !$0.isKind(of: NSPanel.self) &&
                $0 !== closingWindow &&
                $0.title != "" &&
                !$0.title.hasPrefix("Item-") // Filter out internal status bar windows
            }

            LoggerService.shared.debug("Visible windows check: \(visibleWindows.map { $0.title })")

            if visibleWindows.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    // Handle reopening from Dock/Finder
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shouldShowMainWindow = true
        for window in sender.windows {
            if window.identifier?.rawValue == "main" {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task {
            await PermissionsManager.shared.runHealthCheck()
            dictationViewModel.loadAudioDevices()
        }
    }
}

@main
struct WhisperWrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: appDelegate.contentViewModel)
                .environmentObject(appDelegate.dictationViewModel)
                .environmentObject(appDelegate.claudeService)
                .environmentObject(appDelegate.claudePromptManager)
                .frame(minWidth: 760, minHeight: 520)
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
                // MenuBarManager setup removed from here as it is now in AppDelegate
        }
        .defaultSize(width: 920, height: 680)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            // Remove "New Window" command to prevent accidental window creation
            CommandGroup(replacing: .newItem) { }
        }
    }
}
