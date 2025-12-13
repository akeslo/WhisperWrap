import SwiftUI
import AppKit
import Combine

@MainActor
class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var dictationViewModel: DictationViewModel?
    private var contentViewModel: ContentViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var isSetup = false

    private override init() {
        super.init()
    }
    
    func setup(dictationViewModel: DictationViewModel, contentViewModel: ContentViewModel) {
        // Prevent multiple setup calls
        guard !isSetup else { return }
        isSetup = true
        
        self.dictationViewModel = dictationViewModel
        self.contentViewModel = contentViewModel
        
        // Create Status Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Use a simple waveform symbol for menu bar
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisperWrap") {
                let configuredImage = image.withSymbolConfiguration(config)
                configuredImage?.isTemplate = true
                button.image = configuredImage
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked)
        }
        
        // Create Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        
        // Wrap MenuBarView with environment objects
        let menuBarView = MenuBarView()
            .environmentObject(dictationViewModel)
            .environmentObject(contentViewModel)
            
        popover.contentViewController = NSHostingController(rootView: menuBarView)
        self.popover = popover
        
        // Observe State for icon updates AND to close popover when recording starts
        dictationViewModel.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                self?.handleRecordingStateChange(isRecording: isRecording)
            }
            .store(in: &cancellables)

        // Observe permission alerts and auto-open popover when they appear
        dictationViewModel.$activeAlert
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in
                if alert != nil {
                    self?.openPopover()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleRecordingStateChange(isRecording: Bool) {
        // Close popover immediately when recording starts
        if isRecording {
            popover?.performClose(nil)
        }
        
        updateIcon(isRecording: isRecording)
    }
    
    private func updateIcon(isRecording: Bool) {
        guard let button = statusItem?.button else { return }
        
        // Ensure button properties are set for interactivity
        button.target = self
        button.action = #selector(statusBarButtonClicked)
        button.isEnabled = true
        
        if isRecording {
            // Red stop icon when recording
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            if let image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Recording") {
                let coloredImage = image.withSymbolConfiguration(config)
                coloredImage?.isTemplate = false
                button.image = coloredImage
            }
        } else {
            // Simple waveform icon when not recording
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisperWrap") {
                let configuredImage = image.withSymbolConfiguration(config)
                configuredImage?.isTemplate = true
                button.image = configuredImage
            }
        }
    }
    
    @objc private func statusBarButtonClicked() {
        guard let viewModel = dictationViewModel else { return }
        
        if viewModel.isRecording {
            viewModel.stopRecording()
        } else {
            togglePopover()
        }
    }
    
    private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    func openPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
