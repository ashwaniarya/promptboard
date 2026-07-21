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

    let store: LibraryStore
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

    init(store: LibraryStore) {
        self.store = store
    }

    var visibleItems: [LibraryEntry] {
        PromptFilter.filter(store.items, query: searchText)
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

    func copyToClipboard(_ item: LibraryEntry) {
        let text: String
        switch item {
        case .prompt(let prompt): text = prompt.content
        case .skill(let skill): text = skill.body.isEmpty ? skill.description : skill.body
        }
        let pasteboard = NSPasteboard.general
        // clearContents() is required before setString; skipping it makes the write silently fail
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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

    func deleteItem(id: UUID) {
        store.delete(id: id)
        if case .edit(let editingPrompt) = editorMode, editingPrompt.id == id {
            editorMode = nil
        }
    }
}
