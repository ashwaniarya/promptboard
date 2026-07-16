import AppKit
import SwiftUI
import PromptBoardKit

@MainActor
final class OverlayController {
    private let appState: AppState
    private var panel: OverlayPanel?

    init(appState: AppState) {
        self.appState = appState
        appState.requestHide = { [weak self] in self?.hide() }
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
    }

    func hide() {
        appState.resetTransientState()
        panel?.orderOut(nil)
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
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onCancel = { [weak self] in self?.appState.handleEscape() }
        panel.contentView = NSHostingView(rootView: OverlayRootView(appState: appState))

        self.panel = panel
        return panel
    }

    private func currentMouseScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
