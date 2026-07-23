import AppKit
import Carbon

// Registers one or more global Carbon hotkeys and dispatches by EventHotKeyID.
// A single shared event handler reads which hotkey fired — two handlers on the
// same target would each fire for every hotkey, so dispatch-by-id is required.
@MainActor
final class HotKeyManager {
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]

    func register(keyCode: UInt32, modifiers: UInt32, id: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: Self.fourCharCode("PBrd"), id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status != noErr {
            NSLog("PromptBoard: RegisterEventHotKey(id=%u) failed with status %d — is the hotkey already in use?", id, status)
        }
        hotKeyRefs.append(hotKeyRef)
    }

    func teardown() {
        for hotKeyRef in hotKeyRefs where hotKeyRef != nil {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
        handlers.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerProcPtr = { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            // Handlers on GetApplicationEventTarget() fire on the main run loop,
            // so hopping is unnecessary and assumeIsolated is sound here.
            return MainActor.assumeIsolated {
                Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().handle(event)
            }
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if installStatus != noErr {
            NSLog("PromptBoard: InstallEventHandler failed with status %d", installStatus)
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
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
        guard status == noErr, let handler = handlers[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        handler()
        return noErr
    }

    private static func fourCharCode(_ string: String) -> FourCharCode {
        var code: FourCharCode = 0
        for byte in string.utf8.prefix(4) {
            code = (code << 8) | FourCharCode(byte)
        }
        return code
    }
}
