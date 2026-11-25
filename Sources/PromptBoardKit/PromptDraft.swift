import Foundation

public struct PromptDraft: Equatable, Sendable {
    public let promptID: UUID?
    public var title: String
    public var content = ""

    public init(title: String = "") {
        promptID = nil
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(prompt: Prompt) {
        promptID = prompt.id
        title = prompt.title
        content = prompt.content
    }

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
