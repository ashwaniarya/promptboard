import AppKit
import SwiftUI
import PromptBoardKit

@MainActor
final class OverlayController {
    private let appState: AppState
    private var panel: OverlayPanel?
    private var swipeMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        appState.requestHide = { [weak self] in self?.hide() }
        appState.requestFocusEditorTitle = { [weak self] in
            self?.focusTextField(placeholder: Constants.editorTitlePlaceholder)
        }
        appState.requestFocusSearchField = { [weak self] in
            self?.focusTextField(placeholder: Constants.searchFieldPlaceholder)
        }
        appState.requestFocusNewFolder = { [weak self] in
            self?.focusTextField(placeholder: Constants.newFolderPlaceholder)
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        panel.setFrame(currentMouseScreen().frame, display: true)
        appState.beginNewOverlaySession()
        // makeKeyAndOrderFront without NSApp.activate: the .nonactivatingPanel style takes
        // keyboard focus while the previous app stays active, so dismissal restores its focus
        panel.makeKeyAndOrderFront(nil)
        installSwipeMonitor()
    }

    func hide() {
        appState.resetTransientState()
        panel?.orderOut(nil)
        removeSwipeMonitor()
    }

    // A discrete 3-finger trackpad swipe (left/right only — the system reserves an
    // up/down 3-finger swipe for Mission Control and never delivers it to an app) closes
    // the overlay the same way Esc does, staged through any open sub-panel first.
    private func installSwipeMonitor() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            self?.appState.handleEscape()
            return event
        }
    }

    private func removeSwipeMonitor() {
        if let swipeMonitor {
            NSEvent.removeMonitor(swipeMonitor)
        }
        swipeMonitor = nil
    }

    private func ensurePanel() -> OverlayPanel {
        if let panel {
            return panel
        }

        let panel = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        // NSPanel defaults to hiding on app deactivation; a nonactivating panel's app is never active
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onCancel = { [weak self] in self?.appState.handleEscape() }
        panel.contentView = NSHostingView(rootView: OverlayRootView(appState: appState))

        self.panel = panel
        return panel
    }

    func writeContentSnapshot(to path: String) {
        Self.writeSnapshot(of: panel?.contentView, to: path)
    }

    static func writeSnapshot(of contentView: NSView?, to path: String) {
        guard let contentView else {
            NSLog("%@", "PromptBoardDebug snapshot: no content view")
            return
        }
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            NSLog("%@", "PromptBoardDebug snapshot: bitmap rep unavailable for \(contentView.bounds)")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            NSLog("%@", "PromptBoardDebug snapshot: png encode failed")
            return
        }
        do {
            try pngData.write(to: URL(fileURLWithPath: path))
        } catch {
            NSLog("%@", "PromptBoardDebug snapshot: write failed: \(error)")
        }
    }

    // Retries briefly because the target field's AppKit backing view materializes
    // a render pass after the SwiftUI state change that requested the focus move
    private func focusTextField(placeholder: String) {
        Task { @MainActor [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, let panel = self.panel else { return }
                let field = Self.collectTextFields(in: panel.contentView).first {
                    $0.placeholderString == placeholder
                        || $0.placeholderAttributedString?.string == placeholder
                }
                if let field {
                    panel.makeFirstResponder(field)
                    return
                }
            }
        }
    }

    static func collectTextFields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        var fields: [NSTextField] = []
        if let field = view as? NSTextField {
            fields.append(field)
        }
        for subview in view.subviews {
            fields.append(contentsOf: collectTextFields(in: subview))
        }
        return fields
    }

    private func currentMouseScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
