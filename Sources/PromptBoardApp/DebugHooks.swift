import AppKit
import PromptBoardKit

@MainActor
enum DebugHooks {
    static let toggleNotification = "com.arya.PromptBoard.debug.toggle"
    static let snapshotNotification = "com.arya.PromptBoard.debug.snapshot"
    static let newPromptNotification = "com.arya.PromptBoard.debug.newPrompt"
    static let commandKeyNotification = "com.arya.PromptBoard.debug.commandKey"
    static let dumpStateNotification = "com.arya.PromptBoard.debug.dumpState"
    static let dumpPromptsNotification = "com.arya.PromptBoard.debug.dumpPrompts"
    static let expandFirstNotification = "com.arya.PromptBoard.debug.expandFirst"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PROMPTBOARD_DEBUG"] == "1"
    }

    private static var target: DebugHookTarget?

    static func install(overlayController: OverlayController, appState: AppState) {
        guard isEnabled else { return }
        let target = DebugHookTarget(overlayController: overlayController, appState: appState)
        self.target = target

        // Selector observers with .deliverImmediately: the block-based API defaults to
        // .coalesce, and an accessory app is never "active", so deliveries get dropped
        let center = DistributedNotificationCenter.default()
        let hooks: [(String, Selector)] = [
            (toggleNotification, #selector(DebugHookTarget.handleToggle(_:))),
            (snapshotNotification, #selector(DebugHookTarget.handleSnapshot(_:))),
            (newPromptNotification, #selector(DebugHookTarget.handleNewPrompt(_:))),
            (commandKeyNotification, #selector(DebugHookTarget.handleCommandKey(_:))),
            (dumpStateNotification, #selector(DebugHookTarget.handleDumpState(_:))),
            (dumpPromptsNotification, #selector(DebugHookTarget.handleDumpPrompts(_:))),
            (expandFirstNotification, #selector(DebugHookTarget.handleExpandFirst(_:))),
        ]
        for (name, selector) in hooks {
            center.addObserver(
                target,
                selector: selector,
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        NSLog("%@", "PromptBoardDebug hooks installed")
    }
}

@MainActor
private final class DebugHookTarget: NSObject {
    private let overlayController: OverlayController
    private let appState: AppState

    init(overlayController: OverlayController, appState: AppState) {
        self.overlayController = overlayController
        self.appState = appState
    }

    @objc nonisolated func handleToggle(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSLog("%@", "PromptBoardDebug toggle")
            overlayController.toggle()
        }
    }

    @objc nonisolated func handleSnapshot(_ notification: Notification) {
        let outputPath = notification.object as? String ?? "/tmp/promptboard-snapshot.png"
        MainActor.assumeIsolated {
            NSLog("%@", "PromptBoardDebug snapshot -> \(outputPath)")
            overlayController.writeContentSnapshot(to: outputPath)
        }
    }

    @objc nonisolated func handleNewPrompt(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSLog("%@", "PromptBoardDebug newPrompt")
            overlayController.show()
            appState.beginCreating()
        }
    }

    @objc nonisolated func handleCommandKey(_ notification: Notification) {
        guard let characters = notification.object as? String, !characters.isEmpty else { return }
        MainActor.assumeIsolated {
            NSLog("%@", "PromptBoardDebug commandKey ⌘\(characters)")
            sendCommandKeyEquivalent(characters)
        }
    }

    @objc nonisolated func handleDumpState(_ notification: Notification) {
        MainActor.assumeIsolated {
            let keyWindow = NSApp.keyWindow
            let responder = keyWindow?.firstResponder
            let responderType = responder.map { String(describing: type(of: $0)) } ?? "nil"
            let fieldEditorText = (responder as? NSTextView)?.string ?? "<not a text view>"
            NSLog("%@", "PromptBoardDebug state: keyWindow=\(keyWindow != nil) firstResponder=\(responderType) fieldEditorText=\(fieldEditorText)")
            let fieldSummaries = OverlayController.collectTextFields(in: keyWindow?.contentView).map {
                "[placeholder=\($0.placeholderString ?? $0.placeholderAttributedString?.string ?? "nil") value=\($0.stringValue) focused=\($0.currentEditor() != nil)]"
            }
            NSLog("%@", "PromptBoardDebug fields: \(fieldSummaries.joined(separator: " "))")
        }
    }

    @objc nonisolated func handleExpandFirst(_ notification: Notification) {
        let kind = notification.object as? String
        MainActor.assumeIsolated {
            overlayController.show()
            let items = appState.visibleItems
            let target: LibraryEntry?
            switch kind {
            case "skill": target = items.first { $0.kind == .skill }
            case "prompt": target = items.first { $0.kind == .prompt }
            default: target = items.first
            }
            if let target {
                NSLog("%@", "PromptBoardDebug expandFirst -> \(target.title)")
                appState.expand(target)
            }
        }
    }

    @objc nonisolated func handleDumpPrompts(_ notification: Notification) {
        MainActor.assumeIsolated {
            let items = appState.store.items
            let titles = items.map(\.title).joined(separator: " | ")
            NSLog("%@", "PromptBoardDebug items: count=\(items.count) titles=\(titles)")
        }
    }

    // Replays the dispatch path of a real ⌘-key press: key window first, then NSApp.mainMenu
    private func sendCommandKeyEquivalent(_ characters: String) {
        guard let keyWindow = NSApp.keyWindow else {
            NSLog("%@", "PromptBoardDebug commandKey: no key window")
            return
        }
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: keyWindow.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0
        ) else {
            NSLog("%@", "PromptBoardDebug commandKey: could not synthesize event")
            return
        }
        NSApp.sendEvent(event)
    }
}
