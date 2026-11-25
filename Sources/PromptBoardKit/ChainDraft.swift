import Foundation

// Editing state for a chain in the compact quick-insert popup: title, steps, the selected
// step, and a step picker that searches library prompts (chains are never picked).
public struct ChainDraft: Equatable, Sendable {
    public enum PickerRow: Equatable, Sendable {
        case prompt(Prompt)
        case custom(String)
    }

    public let chainID: UUID?
    public var title: String
    public private(set) var steps: [Chain.Step]
    public private(set) var selectedStep: Int?
    public var query = "" {
        didSet { pickerIndex = 0 }
    }
    public private(set) var pickerIndex = 0
    public static let pickerPromptLimit = 6

    public init(chain: Chain? = nil) {
        chainID = chain?.id
        title = chain?.title ?? ""
        steps = chain?.steps ?? []
        selectedStep = steps.isEmpty ? nil : 0
    }

    public init(title: String) {
        self.init()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !steps.contains { step in
                if case .custom(let text) = step { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } else { false }
            }
    }

    public func pickerRows(in items: [LibraryEntry]) -> [PickerRow] {
        let prompts = PromptFilter.quickInsertResults(items, query: query)
            .compactMap { entry -> PickerRow? in if case .prompt(let prompt) = entry { .prompt(prompt) } else { nil } }
            .prefix(Self.pickerPromptLimit)
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Array(prompts) : prompts + [.custom(typed)]
    }

    public mutating func movePicker(by offset: Int, in items: [LibraryEntry]) {
        let count = pickerRows(in: items).count
        pickerIndex = min(max(pickerIndex + offset, 0), max(count - 1, 0))
    }

    public mutating func addPicked(in items: [LibraryEntry]) {
        let rows = pickerRows(in: items)
        guard rows.indices.contains(pickerIndex) else { return }
        switch rows[pickerIndex] {
        case .prompt(let prompt): addLinked(prompt.id)
        case .custom(let text): addCustom(text)
        }
    }

    public mutating func addLinked(_ promptID: UUID) {
        append(.linked(promptID: promptID))
    }

    public mutating func addCustom(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        append(.custom(text: trimmed))
    }

    public mutating func setCustomText(_ text: String, at index: Int) {
        guard steps.indices.contains(index), case .custom = steps[index] else { return }
        steps[index] = .custom(text: text)
    }

    public mutating func selectStep(_ index: Int) {
        if steps.indices.contains(index) { selectedStep = index }
    }

    public mutating func moveSelectedStep(by offset: Int) {
        guard let selectedStep, steps.indices.contains(selectedStep + offset) else { return }
        steps.swapAt(selectedStep, selectedStep + offset)
        self.selectedStep = selectedStep + offset
    }

    public mutating func removeSelectedStep() {
        guard let selectedStep else { return }
        steps.remove(at: selectedStep)
        self.selectedStep = steps.isEmpty ? nil : min(selectedStep, steps.count - 1)
    }

    private mutating func append(_ step: Chain.Step) {
        steps.append(step)
        selectedStep = steps.count - 1
        query = ""
    }
}
