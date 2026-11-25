import Foundation
import Observation
import PromptBoardKit

// State for the cursor quick-insert popup: the query, the ranked prompt and chain
// results (capped), the keyboard selection, and an open chain's step list.
// Independent of the board's AppState.
@MainActor
@Observable
final class QuickInsertModel {
    private let store: LibraryStore
    private let maxResults = 8

    var query = "" {
        didSet {
            selectedIndex = 0
            stepList = nil
        }
    }
    var selectedIndex = 0
    private(set) var stepList: ChainStepList?

    init(store: LibraryStore) {
        self.store = store
    }

    var results: [LibraryEntry] {
        Array(PromptFilter.quickInsertResults(store.items, query: query).prefix(maxResults))
    }

    var selected: LibraryEntry? {
        let current = results
        guard current.indices.contains(selectedIndex) else { return nil }
        return current[selectedIndex]
    }

    func stepList(for chain: Chain) -> ChainStepList {
        ChainStepList(
            chain: chain, prompts: store.prompts,
            progressIndex: store.chainProgress.index(for: chain.id, stepCount: chain.steps.count)
        )
    }

    func progressView(for chain: Chain) -> ChainProgressView {
        ChainProgressView(stepList: stepList(for: chain))
    }

    func reset() {
        query = ""
        selectedIndex = 0
        stepList = nil
    }

    func moveDown() {
        if stepList != nil {
            stepList?.moveDown()
            return
        }
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = min(selectedIndex + 1, count - 1)
    }

    func moveUp() {
        if stepList != nil {
            stepList?.moveUp()
            return
        }
        guard !results.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectStep(_ index: Int) {
        stepList?.select(index)
    }

    func closeStepList() {
        stepList = nil
    }

    // Returns the text to paste, or nil when the action only changed popup state
    // (opened a chain's step list, or restarted a finished chain).
    func activate() -> String? {
        if let stepList {
            switch stepList.activate() {
            case .paste(let text, let nextIndex):
                saveProgress(nextIndex, for: stepList.chain)
                return text
            case .restart:
                restart()
                return nil
            case .nothing:
                return nil
            }
        }
        switch selected {
        case .prompt(let prompt):
            return prompt.content
        case .chain(let chain):
            let opened = stepList(for: chain)
            if !opened.isEmpty { stepList = opened }
            return nil
        case .skill, nil:
            return nil
        }
    }

    func restart() {
        guard let chain = stepList?.chain else { return }
        do {
            try store.chainProgress.reset(for: chain.id)
        } catch {
            NSLog("%@", "PromptBoard: could not reset chain progress: \(error)")
        }
        stepList = stepList(for: chain)
    }

    private func saveProgress(_ index: Int, for chain: Chain) {
        do {
            try store.chainProgress.setIndex(index, for: chain.id)
        } catch {
            NSLog("%@", "PromptBoard: could not save chain progress: \(error)")
        }
    }
}
