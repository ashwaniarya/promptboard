import ApplicationServices

// Thin wrapper over the Accessibility trust check. Insert-at-caret (posting ⌘V and
// reading the caret rect) requires the app to be in System Settings → Privacy →
// Accessibility. A fresh grant may need one app relaunch to take effect.
@MainActor
enum AccessibilityAuthorizer {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    // Shows the system permission dialog (with an "Open System Settings" button) the
    // first time it's called while untrusted. Returns the current trust state.
    @discardableResult
    static func promptIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        // Literal value of kAXTrustedCheckOptionPrompt — the imported global is a
        // non-concurrency-safe `var` under Swift 6 strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
