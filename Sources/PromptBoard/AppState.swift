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
    var editorMode: EditorMode?
    private(set) var overlaySession = 0

    @ObservationIgnored var requestHide: () -> Void = {}

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
