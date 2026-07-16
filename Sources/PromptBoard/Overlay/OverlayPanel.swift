import AppKit

final class OverlayPanel: NSPanel {
    var onCancel: (() -> Void)?

    // Borderless windows refuse key status by default, which would make the search field unfocusable
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
