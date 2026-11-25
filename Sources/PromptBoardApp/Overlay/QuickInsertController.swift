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
    private var clipboardTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private static let skippedPasteboardTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"), TextInserter.transientType,
    ]

    init(store: LibraryStore) {
        self.model = QuickInsertModel(store: store)
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollClipboard() }
        }
    }

    // In-memory only; password-manager (concealed) and our own transient writes are skipped.
    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if let types = pasteboard.types, !Self.skippedPasteboardTypes.isDisjoint(with: types) { return }
        if let text = pasteboard.string(forType: .string) { model.clipboardHistory.record(text) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var contentView: NSView? { panel?.contentView }

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

    private func insert(_ text: String) {
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
        guard let entry = model.selected else {
            NSLog("%@", "PromptBoardDebug debugInsertFirst: no result for \(query)")
            return
        }
        guard let text = model.activate() else {
            NSLog("%@", "PromptBoardDebug debugInsertFirst \(entry.title) nothing to paste")
            return
        }
        NSLog("%@", "PromptBoardDebug debugInsertFirst inserting: \(entry.title) kind=\(entry.kind.rawValue) pasted=\(text.prefix(40))")
        performInsert(text)
    }

    // Debug-only: open the first chain for a query and pick step `step` (0-based),
    // as an arrow-key pick would. A finished chain is restarted, as Enter on "done" is.
    func debugPickStep(query: String, step: Int) {
        model.query = query
        model.selectedIndex = 0
        guard let entry = model.selected, case .chain(let chain) = entry else {
            NSLog("%@", "PromptBoardDebug chainPick: no chain for \(query)")
            return
        }
        let label = "chainPick chain=\(chain.title)"
        guard model.openSteps(), let stepList = model.stepList else {
            NSLog("%@", "PromptBoardDebug \(label) nothing to paste")
            return
        }
        if !stepList.isDone { model.selectStep(step) }
        let peek = model.stepList?.activate()
        guard let text = model.activate(), case .paste(_, let nextIndex)? = peek else {
            NSLog("%@", "PromptBoardDebug \(label) done -> restart")
            model.closeStepList()
            return
        }
        model.closeStepList()
        NSLog("%@", "PromptBoardDebug \(label) pasted=\(text.prefix(40)) next=\(nextIndex)")
        performInsert(text)
    }

    // Debug-only: paste the first clipboard-tab match, then report the history so the
    // harness can confirm the paste did not re-add or reorder anything.
    func debugPasteFirstClip(query: String) {
        model.tab = .clipboard
        model.query = query
        guard let text = model.activate() else {
            NSLog("%@", "PromptBoardDebug pasteFirstClip: no clip for \(query)")
            return
        }
        NSLog("%@", "PromptBoardDebug pasteFirstClip pasted=\(text.prefix(40))")
        performInsert(text)
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

    private func activateSelected() {
        if let text = model.activate() { insert(text) }
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
            rootView: QuickInsertView(model: model, onActivate: { [weak self] in self?.activateSelected() })
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
            let commandOnly = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            // Extract the Sendable keyCode before hopping onto the main actor — NSEvent isn't Sendable.
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                switch keyCode {
                case 125: self.model.moveDown(); return true    // down arrow
                case 126: self.model.moveUp(); return true       // up arrow
                case 48: self.model.switchTab(); return true     // tab
                case 36, 76: self.activateSelected(); return true  // return / keypad enter
                case 15 where commandOnly && self.model.stepList != nil:  // ⌘R
                    self.model.restart()
                    return true
                case 124 where self.model.openSteps(): return true  // right arrow
                case 53:                                           // escape
                    if self.model.stepList != nil { self.model.closeStepList() } else { self.hide() }
                    return true
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
