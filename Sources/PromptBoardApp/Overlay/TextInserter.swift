import AppKit
import CoreGraphics

// Inserts text at the caret of the frontmost app by pasting: save the clipboard,
// set it to the text, synthesize ⌘V, then restore the clipboard. Posting synthetic
// events to another app requires Accessibility permission (checked by the caller).
// Clipboard restore is string-only (an approved v1 limitation).
@MainActor
enum TextInserter {
    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        paste()

        // Restore the previous clipboard once the paste has been delivered.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }

    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
