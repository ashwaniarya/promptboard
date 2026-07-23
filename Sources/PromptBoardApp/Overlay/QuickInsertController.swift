import AppKit
import SwiftUI
import PromptBoardKit

// Orchestrates the cursor quick-insert popup: a compact non-activating panel shown
// at the caret (D3; mouse for now), with an NSEvent key monitor for ↑↓/⏎/esc. On
// select it hides first (focus returns to the target app) then inserts the text.
@MainActor
final class QuickInsertController {
    let model: QuickInsertModel
    private var panel: OverlayPanel?
    private var keyMonitor: Any?

    init(store: LibraryStore) {
        self.model = QuickInsertModel(store: store)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func trigger() {
        // D4 gates on Accessibility permission here.
        let panel = ensurePanel()
        model.reset()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        focusSearchField(in: panel)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func insert(_ prompt: Prompt) {
        let text = prompt.content
        hide()
        // Let focus return to the previously-active app before pasting.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            self?.performInsert(text)
        }
    }

    // Debug-only: insert the top result for a query directly, without showing the
    // popup, so the target app keeps focus during harness end-to-end verification.
    func debugInsertFirst(query: String) {
        model.query = query
        model.selectedIndex = 0
        guard let prompt = model.selected else {
            NSLog("%@", "PromptBoardDebug debugInsertFirst: no result for \(query)")
            return
        }
        NSLog("%@", "PromptBoardDebug debugInsertFirst inserting: \(prompt.title)")
        performInsert(prompt.content)
    }

    // Paste at the caret when trusted; otherwise copy to the clipboard and prompt
    // for Accessibility so the next insert lands at the cursor.
    private func performInsert(_ text: String) {
        if AccessibilityAuthorizer.isTrusted {
            TextInserter.insert(text)
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            AccessibilityAuthorizer.promptIfNeeded()
        }
    }

    private func insertSelected() {
        guard let prompt = model.selected else { return }
        insert(prompt)
    }

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onCancel = { [weak self] in self?.hide() }
        panel.contentViewController = NSHostingController(
            rootView: QuickInsertView(model: model, onInsert: { [weak self] prompt in self?.insert(prompt) })
        )
        self.panel = panel
        return panel
    }

    // Places the popup just below the caret; falls back to the mouse when the caret
    // is unavailable. `topLeft` is the desired top-left corner in Cocoa coordinates.
    private func position(_ panel: OverlayPanel) {
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let gap: CGFloat = 6

        let topLeft: NSPoint
        if let caret = CaretLocator.caretRect() {
            topLeft = NSPoint(x: caret.minX, y: caret.minY - gap)
        } else {
            topLeft = NSEvent.mouseLocation
        }

        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        let screen = NSScreen.screens.first { NSMouseInRect(topLeft, $0.frame, false) }
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        }
        panel.setFrameOrigin(origin)
    }

    // @FocusState is ignored in a non-activating panel; move focus via AppKit.
    private func focusSearchField(in panel: OverlayPanel) {
        Task { @MainActor [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(40))
                guard self != nil, let panel = self?.panel else { return }
                let field = OverlayController.collectTextFields(in: panel.contentView).first {
                    $0.placeholderString == QuickInsertView.searchPlaceholder
                        || $0.placeholderAttributedString?.string == QuickInsertView.searchPlaceholder
                }
                if let field {
                    panel.makeFirstResponder(field)
                    return
                }
            }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event -> NSEvent? in
            let keyCode = event.keyCode
            // Extract the Sendable keyCode before hopping onto the main actor — NSEvent isn't Sendable.
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                switch keyCode {
                case 125: self.model.moveDown(); return true    // down arrow
                case 126: self.model.moveUp(); return true       // up arrow
                case 36, 76: self.insertSelected(); return true  // return / keypad enter
                case 53: self.hide(); return true                // escape
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}
