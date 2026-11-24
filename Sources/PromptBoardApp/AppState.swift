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

    enum ChainEditorMode: Equatable {
        case create
        case edit(Chain)
    }

    let store: LibraryStore
    var searchText = ""
    var columnCount = 3
    var selectedFolder: String?
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
    var chainEditorMode: ChainEditorMode?
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
    @ObservationIgnored var requestFocusNewFolder: () -> Void = {}

    init(store: LibraryStore) {
        self.store = store
    }

    var visibleItems: [LibraryEntry] {
        var items = store.items
        if !Constants.chainsEnabled { items = items.filter { $0.kind != .chain } }
        if let selectedFolder {
            items = items.filter {
                $0.group == selectedFolder || ($0.group?.hasPrefix(selectedFolder + "/") ?? false)
            }
        }
        return PromptFilter.filter(items, query: searchText)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var externalItems: [ExternalItem] {
        // Respect the search box like library items do (by name + origin); external
        // items are group-less so they stay exempt from the group selection.
        showExternalItems ? PromptFilter.filter(store.externalItems, query: searchText) : []
    }

    var folderTree: [FolderNode] {
        FolderNode.build(from: store.items, extraFolderPaths: store.folderPaths)
    }

    func beginNewOverlaySession() {
        overlaySession += 1
    }

    func resetTransientState() {
        searchText = ""
        editorMode = nil
        expandedItem = nil
        chainEditorMode = nil
        skillEditorMode = nil
        convertingPrompt = nil
        adoptingItem = nil
    }

    func handleEscape() {
        if adoptingItem != nil {
            adoptingItem = nil
        } else if convertingPrompt != nil {
            convertingPrompt = nil
        } else if chainEditorMode != nil {
            chainEditorMode = nil
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
        } else if chainEditorMode != nil {
            chainEditorMode = nil
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
        case .chain(let chain): text = ChainBody.render(chain.steps)
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

    func createFolder(named name: String, under parent: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = parent.map { "\($0)/\(trimmed)" } ?? trimmed
        // Prompts and skills share one sidebar folder namespace, so create the directory in
        // both trees. The sidebar surfaces the now-empty folder via the store's on-disk
        // folder enumeration (LibraryStore.folderPaths), unioned into FolderNode.build.
        _ = store.createFolder(kind: .prompt, path: path)
        _ = store.createFolder(kind: .skill, path: path)
    }

    func moveItem(id: UUID, toFolder folder: String?) {
        _ = store.moveItem(id: id, toFolder: folder)
    }

    func beginCreatingSkill() {
        expandedItem = nil
        skillEditorMode = .create
    }

    func beginEditingSkill(_ skill: Skill) {
        expandedItem = nil
        skillEditorMode = .edit(skill)
    }

    func beginCreatingChain() {
        expandedItem = nil
        chainEditorMode = .create
    }

    func beginEditingChain(_ chain: Chain) {
        expandedItem = nil
        chainEditorMode = .edit(chain)
    }

    @discardableResult
    func saveChain(title: String, steps: [Chain.Step]) -> Chain? {
        defer { chainEditorMode = nil }
        switch chainEditorMode {
        case .create:
            return store.addChain(title: title, steps: steps)
        case .edit(let chain):
            store.updateChain(id: chain.id, title: title, steps: steps)
            return store.chains.first { $0.id == chain.id }
        case nil:
            return nil
        }
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
