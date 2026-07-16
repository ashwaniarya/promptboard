import AppKit
import Carbon

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onHotKey: () -> Void

    init(onHotKey: @escaping () -> Void) {
        self.onHotKey = onHotKey
    }

    func register() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerProcPtr = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            // Handlers on GetApplicationEventTarget() fire on the main run loop,
            // so hopping is unnecessary and assumeIsolated is sound here.
            return MainActor.assumeIsolated {
                Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().handleHotKeyPressed()
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
        guard installStatus == noErr else {
            NSLog("PromptBoard: InstallEventHandler failed with status %d", installStatus)
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.fourCharCode("PBrd"), id: 1)
        let registerStatus = RegisterEventHotKey(
            Constants.hotKeyKeyCode,
            Constants.hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            NSLog("PromptBoard: RegisterEventHotKey failed with status %d — is another instance or app using the hotkey?", registerStatus)
        }
    }

    func teardown() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
    }

    private func handleHotKeyPressed() -> OSStatus {
        onHotKey()
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
