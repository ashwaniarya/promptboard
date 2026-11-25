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

    enum Tab: String { case prompts, clipboard }

    var query = "" {
        didSet {
            selectedIndex = 0
            stepList = nil
        }
    }
    var tab = Tab.prompts {
        didSet {
            selectedIndex = 0
            stepList = nil
        }
    }
    var clipboardHistory = ClipboardHistory()
    var selectedIndex = 0
    private(set) var stepList: ChainStepList?
    // chain-state.json is not observable; bumping this redraws rows that read progress.
    private var progressRevision = 0

    init(store: LibraryStore) {
        self.store = store
    }

    var results: [LibraryEntry] {
        Array(PromptFilter.quickInsertResults(store.items, query: query).prefix(maxResults))
    }

    var clipboardResults: [String] {
        Array(clipboardHistory.matches(query).prefix(maxResults))
    }

    var visibleCount: Int { tab == .prompts ? results.count : clipboardResults.count }

    var selected: LibraryEntry? {
        guard tab == .prompts else { return nil }
        let current = results
        guard current.indices.contains(selectedIndex) else { return nil }
        return current[selectedIndex]
    }

    var selectedClip: String? {
        guard tab == .clipboard else { return nil }
        let current = clipboardResults
        guard current.indices.contains(selectedIndex) else { return nil }
        return current[selectedIndex]
    }

    func switchTab() {
        tab = tab == .prompts ? .clipboard : .prompts
    }

    func stepList(for chain: Chain) -> ChainStepList {
        _ = progressRevision
        return ChainStepList(
            chain: chain, prompts: store.prompts,
            progressIndex: store.chainProgress.index(for: chain.id, stepCount: chain.steps.count)
        )
    }

    func progressView(for chain: Chain) -> ChainProgressView {
        ChainProgressView(stepList: stepList(for: chain))
    }

    func reset() {
        query = ""
        tab = .prompts
        selectedIndex = 0
        stepList = nil
    }

    func moveDown() {
        if stepList != nil {
            stepList?.moveDown()
            return
        }
        let count = visibleCount
        guard count > 0 else { return }
        selectedIndex = min(selectedIndex + 1, count - 1)
    }

    func moveUp() {
        if stepList != nil {
            stepList?.moveUp()
            return
        }
        guard visibleCount > 0 else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectStep(_ index: Int) {
        stepList?.select(index)
    }

    func closeStepList() {
        stepList = nil
    }

    // Returns the text to paste, or nil when the action only changed popup state
    // (restarted a finished chain).
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
        if tab == .clipboard { return selectedClip }
        switch selected {
        case .prompt(let prompt):
            return prompt.content
        case .chain(let chain):
            return pasteNext(for: chain)
        case .skill, nil:
            return nil
        }
    }

    func pasteNext(for chain: Chain) -> String? {
        switch stepList(for: chain).activate() {
        case .paste(let text, let nextIndex):
            saveProgress(nextIndex, for: chain)
            return text
        case .restart:
            saveProgress(0, for: chain)
            return nil
        case .nothing:
            return nil
        }
    }

    func openSteps() -> Bool {
        guard stepList == nil, case .chain(let chain)? = selected else { return false }
        let opened = stepList(for: chain)
        guard !opened.isEmpty else { return false }
        stepList = opened
        return true
    }

    func restart() {
        guard let chain = stepList?.chain else { return }
        do {
            try store.chainProgress.reset(for: chain.id)
        } catch {
            NSLog("%@", "PromptBoard: could not reset chain progress: \(error)")
        }
        progressRevision += 1
        stepList = stepList(for: chain)
    }

    private func saveProgress(_ index: Int, for chain: Chain) {
        do {
            try store.chainProgress.setIndex(index, for: chain.id)
        } catch {
            NSLog("%@", "PromptBoard: could not save chain progress: \(error)")
        }
        progressRevision += 1
    }
}
