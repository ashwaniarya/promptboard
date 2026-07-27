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

    enum SkillEditorMode: Equatable {
        case create
        case edit(Skill)
    }

    let store: LibraryStore
    var searchText = ""
    var columnCount = 3
    var selectedGroup: String?
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

    var expandedItem: LibraryEntry?
    var skillEditorMode: SkillEditorMode?
    var convertingPrompt: Prompt?
    var showExternalItems = true
    var adoptingItem: ExternalItem?

    var skillEditorIdentity: String {
        switch skillEditorMode {
        case .create: "create"
        case .edit(let skill): skill.id.uuidString
        case nil: "none"
        }
    }

    @ObservationIgnored var requestHide: () -> Void = {}
    @ObservationIgnored var requestFocusEditorTitle: () -> Void = {}
    @ObservationIgnored var requestFocusSearchField: () -> Void = {}

    init(store: LibraryStore) {
        self.store = store
    }

    var visibleItems: [LibraryEntry] {
        var items = store.items
        if let selectedGroup {
            items = items.filter { $0.group == selectedGroup }
        }
        return PromptFilter.filter(items, query: searchText)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var externalItems: [ExternalItem] {
        showExternalItems ? store.externalItems : []
    }

    var groupCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in store.items {
            if let group = item.group { counts[group, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.name < $1.name }
    }

    func beginNewOverlaySession() {
        overlaySession += 1
    }

    func resetTransientState() {
        searchText = ""
        editorMode = nil
        expandedItem = nil
        skillEditorMode = nil
        convertingPrompt = nil
        adoptingItem = nil
    }

    func handleEscape() {
        if adoptingItem != nil {
            adoptingItem = nil
        } else if convertingPrompt != nil {
            convertingPrompt = nil
        } else if skillEditorMode != nil {
            skillEditorMode = nil
        } else if editorMode != nil {
            editorMode = nil
        } else if expandedItem != nil {
            expandedItem = nil
        } else if !searchText.isEmpty {
            searchText = ""
        } else {
            requestHide()
        }
    }

    func handleBackgroundClick() {
        if adoptingItem != nil {
            adoptingItem = nil
        } else if convertingPrompt != nil {
            convertingPrompt = nil
        } else if skillEditorMode != nil {
            skillEditorMode = nil
        } else if editorMode != nil {
            editorMode = nil
        } else if expandedItem != nil {
            expandedItem = nil
        } else {
            requestHide()
        }
    }

    func expand(_ item: LibraryEntry) {
        expandedItem = item
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

    func beginCreatingSkill() {
        expandedItem = nil
        skillEditorMode = .create
    }

    func beginEditingSkill(_ skill: Skill) {
        expandedItem = nil
        skillEditorMode = .edit(skill)
    }

    func beginConverting(_ prompt: Prompt) {
        convertingPrompt = prompt
    }

    func beginAdopting(_ item: ExternalItem) {
        adoptingItem = item
    }

    func confirmAdopt(mode: LibraryRepository.AdoptMode) {
        guard let item = adoptingItem else { return }
        store.adoptExternal(item, mode: mode)
        adoptingItem = nil
    }

    // Create's first save materializes the folder, then reopens in edit mode so
    // file management unlocks (the editor was empty in create mode).
    @discardableResult
    func saveNewSkill(name: String, description: String, group: String?, body: String) -> Skill? {
        guard let skill = store.createSkill(name: name, description: description, group: group, body: body) else {
            skillEditorMode = nil
            return nil
        }
        skillEditorMode = .edit(skill)
        return skill
    }

    func confirmConvert(prompt: Prompt, name: String, description: String, group: String?, keepOriginal: Bool) {
        let skill = store.promotePromptToSkill(
            promptID: prompt.id, name: name, description: description, group: group, removingPrompt: !keepOriginal
        )
        convertingPrompt = nil
        if let skill { skillEditorMode = .edit(skill) }
    }
}
