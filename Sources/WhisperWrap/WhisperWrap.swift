// The Swift Programming Language
// https://docs.swift.org/swift-book

import Combine
import SwiftUI
import AppKit
import UserNotifications

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
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.dictationViewModel.stopRecording()
                }
            }
        }
        completionHandler()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Move ownership of ViewModels here to ensure they exist at launch
    var contentViewModel = ContentViewModel()
    var dictationViewModel = DictationViewModel()
    let claudeService = ClaudeService()
    let claudePromptManager = ClaudePromptManager()
    
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

        // Notification setup
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

        // Setup Menu Bar immediately on launch
        MenuBarManager.shared.setup(dictationViewModel: dictationViewModel, contentViewModel: contentViewModel)

        // Run permission health check on startup
        Task { await PermissionsManager.shared.runHealthCheck() }

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
        
        // Default to accessory mode (hidden from dock) until we decide otherwise
        NSApp.setActivationPolicy(.accessory)
        
        // Aggressively close any windows that appear before we're ready
        // Run this check multiple times in the first second to catch SwiftUI window creation
        for delay in [0.0, 0.1, 0.2, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                if !self.shouldShowMainWindow {
                    for window in NSApp.windows {
                        if window.isVisible && !window.isKind(of: NSPanel.self) {
                            self.logToFile("Force closing window at delay \(delay): \(window.title)")
                            window.orderOut(nil)
                        }
                    }
                }
            }
        }
        
        // Check for Manual Launch (Finder/Dock Double Click)
        // If launched by Finder (Apple Event 'oapp'), we want to show the window.
        // Login items usually launch without a standard 'oapp' event or with specific parameters we can filtering.
        let event = NSAppleEventManager.shared().currentAppleEvent
        if let event = event,
           event.eventClass == kCoreEventClass,
           event.eventID == kAEOpenApplication {
            
            // Check for simulation flag
            if ProcessInfo.processInfo.arguments.contains("-backgroundLaunch") {
                self.logToFile("Startup: Simulation flag detected, ignoring Apple Event")
                print("Startup: Simulation flag detected, ignoring Apple Event")
            } else {
                self.logToFile("Startup: Detected Manual Launch (Apple Event), showing window")
                print("Startup: Detected Manual Launch (Apple Event), showing window")
                shouldShowMainWindow = true
                showMainWindow()
            }
        }
        
        // WhisperKit needs no setup — stay hidden at launch unless manually opened
        logToFile("Startup: WhisperKit ready, staying hidden")
        print("Startup: WhisperKit ready, staying hidden")

        // Force close check on launch
        if !shouldShowMainWindow {
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
    }
    
    private func showMainWindow() {
        logToFile("showMainWindow called")
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func logToFile(_ text: String) {
        let url = URL(fileURLWithPath: "/tmp/ww_internal.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = (text + "\n").data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - App Location Check

    private func checkAppLocation() {
        let bundlePath = Bundle.main.bundlePath
        // Already in /Applications
        if bundlePath.hasPrefix("/Applications") { return }

        // Don't nag if user already dismissed
        if UserDefaults.standard.bool(forKey: "dismissedAppLocationPrompt") { return }

        // Don't prompt during development builds from Xcode or swift build
        if bundlePath.contains(".build/") || bundlePath.contains("DerivedData") { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showMoveToApplicationsAlert()
        }
    }

    private func showMoveToApplicationsAlert() {
        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "WhisperWrap is running from:\n\(Bundle.main.bundlePath)\n\nWould you like to move it to /Applications for easier access and updates?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move to /Applications")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")

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
        let fileManager = FileManager.default
        let appsDir = URL(fileURLWithPath: "/Applications")
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        let appName = source.lastPathComponent
        let destination = appsDir.appendingPathComponent(appName)

        logToFile("Move: source=\(source.path) dest=\(destination.path)")
        logToFile("Move: source exists=\(fileManager.fileExists(atPath: source.path)) isDir=\(source.hasDirectoryPath)")

        // Verify /Applications exists
        guard fileManager.fileExists(atPath: appsDir.path) else {
            logToFile("Move: /Applications does not exist")
            showMoveError("/Applications folder not found")
            return
        }

        // Remove existing copy at destination
        if fileManager.fileExists(atPath: destination.path) {
            logToFile("Move: removing existing at destination")
            do {
                try fileManager.removeItem(at: destination)
            } catch {
                logToFile("Move: FAILED to remove existing: \(error)")
                showMoveError("Could not replace existing app: \(error.localizedDescription)")
                return
            }
        }

        // Copy to ~/Applications
        do {
            try fileManager.copyItem(at: source, to: destination)
            logToFile("Move: copy succeeded, exists at dest=\(fileManager.fileExists(atPath: destination.path))")
        } catch {
            logToFile("Move: FAILED to copy: \(error)")
            showMoveError("Could not move app: \(error.localizedDescription)")
            return
        }

        // Relaunch from new location using a fully detached process
        logToFile("Move: attempting relaunch from \(destination.path)")
        let escapedDest = destination.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedSource = source.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = "sleep 1 && rm -rf '\(escapedSource)' && open '\(escapedDest)'"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = ["/bin/bash", "-c", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.qualityOfService = .background
        do {
            try task.run()
            logToFile("Move: detached relaunch started, terminating current instance")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        } catch {
            logToFile("Move: FAILED to launch relaunch script: \(error)")
            showMoveError("Could not relaunch app: \(error.localizedDescription)")
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
            
            print("Visible windows check: \(visibleWindows.map { $0.title })")
            
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
        Task { await PermissionsManager.shared.runHealthCheck() }
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
                .frame(minWidth: 600, minHeight: 400)
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
                // MenuBarManager setup removed from here as it is now in AppDelegate
        }
        .defaultSize(width: 800, height: 600)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            // Remove "New Window" command to prevent accidental window creation
            CommandGroup(replacing: .newItem) { }
        }
    }
}
