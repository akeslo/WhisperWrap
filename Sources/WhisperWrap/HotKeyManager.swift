import Carbon
import SwiftUI

class HotKeyManager: ObservableObject {
    /// The main dictation toggle hotkey (id 1) is user-configurable and mirrored here for display.
    @Published var key: Int = kVK_Space
    @Published var modifiers: Int = optionKey

    private struct Registration {
        var ref: EventHotKeyRef?
        var handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private static let signature = OSType(0x57574150) // 'WWAP'
    private static let mainHotKeyID: UInt32 = 1

    private let carbonCallback: EventHandlerUPP = { _, event, userData in
        guard let userData = userData, let event = event else { return noErr }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, let registration = manager.registrations[hotKeyID.id] else { return noErr }
        registration.handler()
        return noErr
    }

    init() {
        installEventHandler()
    }

    deinit {
        for id in registrations.keys {
            if let ref = registrations[id]?.ref {
                UnregisterEventHotKey(ref)
            }
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Registers the main, user-configurable dictation toggle hotkey.
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        self.key = keyCode
        self.modifiers = modifiers
        registerHotKey(id: Self.mainHotKeyID, keyCode: keyCode, modifiers: modifiers, handler: handler)
    }

    /// Registers an additional, fixed hotkey (e.g. show-last-result, select-prompt) identified by `id`.
    func registerAdditional(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        registerHotKey(id: id, keyCode: keyCode, modifiers: modifiers, handler: handler)
    }

    private func registerHotKey(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        unregister(id: id)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = Self.signature
        hotKeyID.id = id

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(modifiers),
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)

        if status != noErr {
            print("Failed to register hotkey \(id): \(status)")
            return
        }
        registrations[id] = Registration(ref: hotKeyRef, handler: handler)
    }

    private func unregister(id: UInt32) {
        if let ref = registrations[id]?.ref {
            UnregisterEventHotKey(ref)
        }
        registrations.removeValue(forKey: id)
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
