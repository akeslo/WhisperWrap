import Carbon
import SwiftUI

class HotKeyManager: ObservableObject {
    var eventHandler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    // Default: Option + Space
    @Published var key: Int = kVK_Space
    @Published var modifiers: Int = optionKey
    
    // Carbon event handler callback
    private let carbonCallback: EventHandlerUPP = { _, _, userData in
        guard let userData = userData else { return noErr }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.eventHandler?()
        return noErr
    }
    
    init() {
        installEventHandler()
    }
    
    deinit {
        unregister()
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
    
    func register(keyCode: Int, modifiers: Int) {
        unregister()
        
        self.key = keyCode
        self.modifiers = modifiers
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x57574150) // 'WWAP'
        hotKeyID.id = UInt32(1)
        
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        
        if status != noErr {
            print("Failed to register hotkey: \(status)")
        } else {
            print("Hotkey registered")
        }
    }
    
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(GetApplicationEventTarget(),
                            carbonCallback,
                            1,
                            &eventType,
                            selfPointer,
                            &eventHandlerRef)
    }
}
