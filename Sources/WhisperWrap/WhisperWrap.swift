// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var contentViewModel: ContentViewModel?
    var dictationViewModel: DictationViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    @MainActor @objc private func windowDidBecomeVisible(_ notification: Notification) {
        // Ignore panels (like HUD)
        if let window = notification.object as? NSWindow, window.isKind(of: NSPanel.self) {
            return
        }
        
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
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct WhisperWrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Shared state
    @StateObject private var contentViewModel = ContentViewModel()
    @StateObject private var dictationViewModel = DictationViewModel()



    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: contentViewModel)
                .environmentObject(dictationViewModel)
                .frame(minWidth: 600, minHeight: 400)
                .handlesExternalEvents(preferring: Set(arrayLiteral: "main"), allowing: Set(arrayLiteral: "*"))
                .onAppear {
                    MenuBarManager.shared.setup(dictationViewModel: dictationViewModel, contentViewModel: contentViewModel)
                }
        }
        .defaultSize(width: 800, height: 600)
        .handlesExternalEvents(matching: Set(arrayLiteral: "main"))
        .commands {
            // Remove "New Window" command to prevent accidental window creation
            CommandGroup(replacing: .newItem) { }
        }
    }
}
