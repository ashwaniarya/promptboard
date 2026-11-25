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
        focusField(placeholder: QuickInsertView.searchPlaceholder)
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
        if let text = model.activate() {
            insert(text)
        } else if model.chainDraft != nil {
            focusChainEditor()
        } else if model.promptDraft != nil {
            focusPromptEditor()
        }
    }

    private func focusPromptEditor() {
        if model.promptDraft?.title.isEmpty ?? true {
            focusField(placeholder: QuickInsertView.promptTitlePlaceholder)
            return
        }
        Task { @MainActor [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(40))
                guard let panel = self?.panel else { return }
                if let textView = Self.collectTextViews(in: panel.contentView).first {
                    panel.makeFirstResponder(textView)
                    return
                }
            }
        }
    }

    // A focused NSTextField hosts its field editor as a subview; only the TextEditor's view counts.
    private static func collectTextViews(in view: NSView?) -> [NSTextView] {
        guard let view else { return [] }
        let own = (view as? NSTextView).map { $0.isFieldEditor || !$0.isEditable ? [] : [$0] } ?? []
        return own + view.subviews.flatMap { collectTextViews(in: $0) }
    }

    private func leavePromptEditor(saving: Bool) {
        if saving {
            guard model.savePromptDraft() else { return }
        } else {
            model.cancelPromptDraft()
        }
        focusField(placeholder: QuickInsertView.searchPlaceholder)
    }

    // Back button and esc: drop any open draft unsaved and return to the list.
    func backToList() {
        model.cancelChainDraft()
        model.cancelPromptDraft()
        focusField(placeholder: QuickInsertView.searchPlaceholder)
    }

    private func editSelected() {
        guard model.beginEditSelected() else { return }
        if model.chainDraft != nil { focusChainEditor() } else { focusPromptEditor() }
    }

    private func focusChainEditor() {
        let needsTitle = model.chainDraft?.chainID == nil && model.chainDraft?.title.isEmpty ?? true
        focusField(placeholder: needsTitle ? QuickInsertView.chainTitlePlaceholder : QuickInsertView.stepSearchPlaceholder)
    }

    private func leaveChainEditor(saving: Bool) {
        if saving {
            guard model.saveChainDraft() else { return }
        } else {
            model.cancelChainDraft()
        }
        focusField(placeholder: QuickInsertView.searchPlaceholder)
    }

    private var isStepSearchFocused: Bool {
        guard let editor = panel?.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField else { return false }
        return field.placeholderString == QuickInsertView.stepSearchPlaceholder
            || field.placeholderAttributedString?.string == QuickInsertView.stepSearchPlaceholder
    }

    // Keys while the chain editor is open. ⏎ adds only from the step search field;
    // elsewhere (title, custom step text) it jumps there instead.
    private func handleChainEditorKey(keyCode: UInt16, chordFlags: NSEvent.ModifierFlags, character: String?) -> Bool {
        switch keyCode {
        case 125, 126:
            let offset = keyCode == 125 ? 1 : -1
            if chordFlags == .option {
                model.updateChainDraft { $0.moveSelectedStep(by: offset) }
            } else {
                model.movePicker(by: offset)
            }
            return true
        case 36, 76:
            if chordFlags == .command {
                model.addTypedCustomStep()
            } else if isStepSearchFocused {
                model.addPickedStep()
            } else {
                focusField(placeholder: QuickInsertView.stepSearchPlaceholder)
            }
            return true
        case 51 where chordFlags == .command:
            model.updateChainDraft { $0.removeSelectedStep() }
            return true
        case 53:
            leaveChainEditor(saving: false)
            return true
        case _ where chordFlags == .command && character == "s":
            leaveChainEditor(saving: true)
            return true
        default:
            return false
        }
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
            rootView: QuickInsertView(
                model: model,
                onActivate: { [weak self] in self?.activateSelected() },
                onEdit: { [weak self] in self?.editSelected() },
                onBack: { [weak self] in self?.backToList() }
            )
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
    private func focusField(placeholder: String) {
        Task { @MainActor [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(40))
                guard self != nil, let panel = self?.panel else { return }
                let field = OverlayController.collectTextFields(in: panel.contentView).first {
                    $0.placeholderString == placeholder || $0.placeholderAttributedString?.string == placeholder
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
            // Caps Lock is a toggle, and arrow keys always carry .function/.numericPad: none of them is a chord.
            let chordFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .function, .numericPad])
            let character = event.charactersIgnoringModifiers?.lowercased()
            let isCommandR = chordFlags == .command && character == "r"
            let noChord = chordFlags.isEmpty
            // Extract the Sendable keyCode before hopping onto the main actor — NSEvent isn't Sendable.
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if self.model.chainDraft != nil {
                    return self.handleChainEditorKey(keyCode: keyCode, chordFlags: chordFlags, character: character)
                }
                if self.model.promptDraft != nil {
                    switch keyCode {
                    case 53: self.leavePromptEditor(saving: false); return true
                    case _ where chordFlags == .command && character == "s": self.leavePromptEditor(saving: true); return true
                    default: return false
                    }
                }
                let inPromptList = self.model.tab == .prompts && self.model.stepList == nil
                switch keyCode {
                case _ where inPromptList && chordFlags == .command && character == "e":
                    self.editSelected()
                    return true
                case _ where inPromptList && chordFlags == .command && character == "n":
                    self.model.beginNewChain()
                    self.focusChainEditor()
                    return true
                case _ where inPromptList && chordFlags == [.command, .shift] && character == "n":
                    self.model.beginNewPrompt()
                    self.focusPromptEditor()
                    return true
                case _ where isCommandR && self.model.stepList != nil:
                    self.model.restart()
                    return true
                case 125: self.model.moveDown(); return true    // down arrow
                case 126: self.model.moveUp(); return true       // up arrow
                case 48: self.model.switchTab(); return true     // tab
                case 36, 76: self.activateSelected(); return true  // return / keypad enter
                case 124 where noChord && self.model.openSteps(): return true  // right arrow
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
