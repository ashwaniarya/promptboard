import Observation
import PromptBoardKit

// State for the cursor quick-insert popup: the query, the ranked prompts-only
// results (capped), and the keyboard selection. Independent of the board's AppState.
@MainActor
@Observable
final class QuickInsertModel {
    private let store: LibraryStore
    private let maxResults = 8

    var query = "" {
        didSet { selectedIndex = 0 }
    }
    var selectedIndex = 0

    init(store: LibraryStore) {
        self.store = store
    }

    var results: [Prompt] {
        Array(PromptFilter.quickInsertResults(store.prompts, query: query).prefix(maxResults))
    }

    var selected: Prompt? {
        let current = results
        guard current.indices.contains(selectedIndex) else { return nil }
        return current[selectedIndex]
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }

    func moveDown() {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = min(selectedIndex + 1, count - 1)
    }

    func moveUp() {
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }
}
