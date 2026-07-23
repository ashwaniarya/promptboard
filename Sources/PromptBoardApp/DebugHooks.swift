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
    static let createSampleSkillNotification = "com.arya.PromptBoard.debug.createSampleSkill"
    static let editFirstSkillNotification = "com.arya.PromptBoard.debug.editFirstSkill"
    static let convertFirstPromptNotification = "com.arya.PromptBoard.debug.convertFirstPrompt"
    static let newSkillNotification = "com.arya.PromptBoard.debug.newSkill"
    static let confirmConvertFirstNotification = "com.arya.PromptBoard.debug.confirmConvertFirst"
    static let addSampleFilesNotification = "com.arya.PromptBoard.debug.addSampleFiles"
    static let quickInsertNotification = "com.arya.PromptBoard.debug.quickInsert"
    static let testInsertClipboardNotification = "com.arya.PromptBoard.debug.testInsertClipboard"
    static let insertFirstResultNotification = "com.arya.PromptBoard.debug.insertFirstResult"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PROMPTBOARD_DEBUG"] == "1"
    }

    private static var target: DebugHookTarget?

    static func install(overlayController: OverlayController, appState: AppState, quickInsertController: QuickInsertController) {
        guard isEnabled else { return }
        let target = DebugHookTarget(
            overlayController: overlayController, appState: appState, quickInsertController: quickInsertController
        )
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
            (createSampleSkillNotification, #selector(DebugHookTarget.handleCreateSampleSkill(_:))),
            (editFirstSkillNotification, #selector(DebugHookTarget.handleEditFirstSkill(_:))),
            (convertFirstPromptNotification, #selector(DebugHookTarget.handleConvertFirstPrompt(_:))),
            (newSkillNotification, #selector(DebugHookTarget.handleNewSkill(_:))),
            (confirmConvertFirstNotification, #selector(DebugHookTarget.handleConfirmConvertFirst(_:))),
            (addSampleFilesNotification, #selector(DebugHookTarget.handleAddSampleFiles(_:))),
            (quickInsertNotification, #selector(DebugHookTarget.handleQuickInsert(_:))),
            (testInsertClipboardNotification, #selector(DebugHookTarget.handleTestInsertClipboard(_:))),
            (insertFirstResultNotification, #selector(DebugHookTarget.handleInsertFirstResult(_:))),
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
    private let quickInsertController: QuickInsertController

    init(overlayController: OverlayController, appState: AppState, quickInsertController: QuickInsertController) {
        self.overlayController = overlayController
        self.appState = appState
        self.quickInsertController = quickInsertController
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

    @objc nonisolated func handleCreateSampleSkill(_ notification: Notification) {
        let name = notification.object as? String ?? "harness-skill"
        MainActor.assumeIsolated {
            let skill = appState.store.createSkill(
                name: name, description: "made by the debug harness", group: "Debug", body: "# \(name)\n\nBody."
            )
            NSLog("%@", "PromptBoardDebug createSampleSkill -> \(skill?.name ?? "nil")")
        }
    }

    @objc nonisolated func handleEditFirstSkill(_ notification: Notification) {
        MainActor.assumeIsolated {
            overlayController.show()
            guard case .skill(let skill)? = appState.store.items.first(where: { $0.kind == .skill }) else {
                NSLog("%@", "PromptBoardDebug editFirstSkill -> no skill")
                return
            }
            NSLog("%@", "PromptBoardDebug editFirstSkill -> \(skill.name)")
            appState.beginEditingSkill(skill)
        }
    }

    @objc nonisolated func handleConvertFirstPrompt(_ notification: Notification) {
        MainActor.assumeIsolated {
            overlayController.show()
            guard case .prompt(let prompt)? = appState.store.items.first(where: { $0.kind == .prompt }) else {
                NSLog("%@", "PromptBoardDebug convertFirstPrompt -> no prompt")
                return
            }
            NSLog("%@", "PromptBoardDebug convertFirstPrompt -> \(prompt.title)")
            appState.beginConverting(prompt)
        }
    }

    @objc nonisolated func handleNewSkill(_ notification: Notification) {
        MainActor.assumeIsolated {
            overlayController.show()
            appState.beginCreatingSkill()
            NSLog("%@", "PromptBoardDebug newSkill")
        }
    }

    @objc nonisolated func handleConfirmConvertFirst(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard case .prompt(let prompt)? = appState.store.items.first(where: { $0.kind == .prompt }) else {
                NSLog("%@", "PromptBoardDebug confirmConvertFirst -> no prompt")
                return
            }
            appState.confirmConvert(
                prompt: prompt, name: prompt.title, description: "converted by harness", group: nil, keepOriginal: false
            )
            NSLog("%@", "PromptBoardDebug confirmConvertFirst -> \(prompt.title)")
        }
    }

    @objc nonisolated func handleQuickInsert(_ notification: Notification) {
        let query = notification.object as? String
        MainActor.assumeIsolated {
            quickInsertController.trigger()
            if let query { quickInsertController.model.query = query }
            let results = quickInsertController.model.results
            NSLog("%@", "PromptBoardDebug quickInsert query=\(query ?? "") results=\(results.count): \(results.map(\.title).joined(separator: " | "))")
        }
    }

    @objc nonisolated func handleInsertFirstResult(_ notification: Notification) {
        let query = notification.object as? String ?? ""
        MainActor.assumeIsolated {
            quickInsertController.debugInsertFirst(query: query)
        }
    }

    @objc nonisolated func handleTestInsertClipboard(_ notification: Notification) {
        MainActor.assumeIsolated {
            let trusted = AccessibilityAuthorizer.isTrusted
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString("SENTINEL-CLIP", forType: .string)
            TextInserter.insert("HARNESS-INSERTED")
            let immediate = pasteboard.string(forType: .string) ?? "nil"
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                let restored = NSPasteboard.general.string(forType: .string) ?? "nil"
                NSLog("%@", "PromptBoardDebug testInsertClipboard trusted=\(trusted) immediate=\(immediate) restored=\(restored)")
            }
        }
    }

    @objc nonisolated func handleAddSampleFiles(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard case .skill(let skill)? = appState.store.items.first(where: { $0.kind == .skill }) else {
                NSLog("%@", "PromptBoardDebug addSampleFiles -> no skill")
                return
            }
            _ = appState.store.writeSkillFile(id: skill.id, relativePath: "examples/note.md", data: Data("nested text".utf8))
            _ = appState.store.writeSkillFile(id: skill.id, relativePath: "logo.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0xFE]))
            let binaryText = appState.store.skillFileText(id: skill.id, relativePath: "logo.png")
            var files: [String] = []
            if case .skill(let refreshed)? = appState.store.items.first(where: { $0.id == skill.id }) {
                files = refreshed.files.map(\.relativePath)
            }
            NSLog("%@", "PromptBoardDebug addSampleFiles -> files=\(files) binaryText=\(binaryText == nil ? "nil" : "text")")
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
