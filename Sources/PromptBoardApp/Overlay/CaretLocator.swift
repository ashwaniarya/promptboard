import AppKit
import ApplicationServices

// Reads the text caret's screen rect via the Accessibility API. Returns nil when
// unavailable — no focused text element, an app that doesn't expose AX, or missing
// Accessibility permission — and the caller falls back to the mouse location.
enum CaretLocator {
    static func caretRect() -> NSRect? {
        let systemWide = AXUIElementCreateSystemWide()

        guard let focused = copyAttribute(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        let element = focused as! AXUIElement

        guard let rangeRef = copyAttribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        let axRange = rangeRef as! AXValue

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsRef
        ) == .success, let bounds = boundsRef else { return nil }
        let axBounds = bounds as! AXValue

        var rect = CGRect.zero
        guard AXValueGetValue(axBounds, .cgRect, &rect) else { return nil }
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.height > 0 else { return nil }

        // AX rects use a top-left origin measured from the primary screen; flip to Cocoa bottom-left.
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let cocoaY = primaryHeight - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: cocoaY, width: rect.width, height: rect.height)
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
