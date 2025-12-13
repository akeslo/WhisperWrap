// The Swift Programming Language
// https://docs.swift.org/swift-book

import Combine
import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // Move ownership of ViewModels here to ensure they exist at launch
    var contentViewModel = ContentViewModel()
    var dictationViewModel = DictationViewModel()
    
    // Flag to control whether the main window should be shown
    var shouldShowMainWindow = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Connect dependencies
        dictationViewModel.contentViewModel = contentViewModel
        
        // Setup Menu Bar immediately on launch
        MenuBarManager.shared.setup(dictationViewModel: dictationViewModel, contentViewModel: contentViewModel)
        
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
        
        // Check startup state after environment check settles
        // We wait for isCheckingEnv to go from true -> false
        contentViewModel.$isCheckingEnv
            .receive(on: RunLoop.main)
            .dropFirst() // Ignore initial value
            .sink { [weak self] isChecking in
                guard let self = self else { return }
                if !isChecking {
                    // Check complete. If not installed, we MUST show setup.
                    if !self.contentViewModel.whisperInstalled {
                        self.logToFile("Startup: Prereqs not met, forcing window open")
                        print("Startup: Prereqs not met, forcing window open")
                        self.shouldShowMainWindow = true
                        self.showMainWindow()
                    } else {
                        self.logToFile("Startup: Prereqs met, staying hidden")
                        print("Startup: Prereqs met, staying hidden")
                    }
                }
            }
            .store(in: &cancellables)
            
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
}

@main
struct WhisperWrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: appDelegate.contentViewModel)
                .environmentObject(appDelegate.dictationViewModel)
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
