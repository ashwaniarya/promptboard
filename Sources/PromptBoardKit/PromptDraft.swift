import Foundation

public struct PromptDraft: Equatable, Sendable {
    public var title: String
    public var content = ""

    public init(title: String = "") {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
