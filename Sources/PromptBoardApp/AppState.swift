import AppKit
import Observation
import PromptBoardKit

@MainActor
@Observable
final class AppState {
    enum EditorMode: Equatable, Hashable {
        case new
        case edit(Prompt)
    }

    let store: PromptStore
    var searchText = ""
    private(set) var overlaySession = 0

    // SwiftUI @FocusState writes are ignored while the app is inactive — and a
    // nonactivating panel's app is never active — so focus moves are delegated
    // to the AppKit layer through these callbacks
    var editorMode: EditorMode? {
        didSet {
            guard oldValue != editorMode else { return }
            if editorMode != nil {
                requestFocusEditorTitle()
            } else {
                requestFocusSearchField()
            }
        }
    }

    @ObservationIgnored var requestHide: () -> Void = {}
    @ObservationIgnored var requestFocusEditorTitle: () -> Void = {}
    @ObservationIgnored var requestFocusSearchField: () -> Void = {}

    init(store: PromptStore) {
        self.store = store
    }

    var visiblePrompts: [Prompt] {
        PromptFilter.filter(store.prompts, query: searchText)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func beginNewOverlaySession() {
        overlaySession += 1
    }

    func resetTransientState() {
        searchText = ""
        editorMode = nil
    }

    func handleEscape() {
        if editorMode != nil {
            editorMode = nil
        } else if !searchText.isEmpty {
            searchText = ""
        } else {
            requestHide()
        }
    }

    func handleBackgroundClick() {
        if editorMode != nil {
            editorMode = nil
        } else {
            requestHide()
        }
    }

    func copyToClipboard(_ prompt: Prompt) {
        let pasteboard = NSPasteboard.general
        // clearContents() is required before setString; skipping it makes the write silently fail
        pasteboard.clearContents()
        pasteboard.setString(prompt.content, forType: .string)
    }

    func beginEditing(_ prompt: Prompt) {
        editorMode = .edit(prompt)
    }

    func beginCreating() {
        editorMode = .new
    }

    func saveEditor(title: String, content: String) {
        switch editorMode {
        case .new:
            store.add(title: title, content: content)
        case .edit(let prompt):
            store.update(id: prompt.id, title: title, content: content)
        case nil:
            break
        }
        editorMode = nil
    }

    func deletePrompt(id: UUID) {
        store.delete(id: id)
        if case .edit(let editingPrompt) = editorMode, editingPrompt.id == id {
            editorMode = nil
        }
    }
}
