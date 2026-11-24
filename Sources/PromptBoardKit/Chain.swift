import Foundation

public struct Chain: Identifiable, Codable, Equatable, Hashable, Sendable {
    public enum Step: Codable, Equatable, Hashable, Sendable {
        case linked(promptID: UUID)
        case custom(text: String)
    }

    public let id: UUID
    public var title: String
    public var steps: [Step]
    public var group: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        steps: [Step],
        group: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.steps = steps
        self.group = group
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var customStepText: String {
        steps.compactMap { if case .custom(let text) = $0 { text } else { nil } }.joined(separator: "\n")
    }
}

// Body syntax: `- @<uuid>` for a linked step; a backtick fence (optionally with an info
// string), the text, then the bare fence for a custom step. Anything else is ignored.
public enum ChainBody {
    private static let linkPrefix = "- @"

    public static func render(_ steps: [Chain.Step]) -> String {
        steps.map { step in
            switch step {
            case .linked(let promptID):
                return linkPrefix + promptID.uuidString
            case .custom(let text):
                let trimmed = text.trimmingCharacters(in: .newlines)
                let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: trimmed) + 1))
                return "\(fence)\n\(trimmed)\n\(fence)"
            }
        }.joined(separator: "\n\n")
    }

    public static func parse(_ body: String) -> [Chain.Step] {
        let lines = body.components(separatedBy: "\n")
        var steps: [Chain.Step] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if line.hasPrefix(linkPrefix) {
                if let id = UUID(uuidString: String(line.dropFirst(linkPrefix.count))) {
                    steps.append(.linked(promptID: id))
                }
            } else if line.hasPrefix("```") {
                let fence = String(line.prefix { $0 == "`" })
                var textLines: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != fence {
                    textLines.append(lines[index])
                    index += 1
                }
                index += 1
                steps.append(.custom(text: textLines.joined(separator: "\n")))
            }
        }
        return steps
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            current = character == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}
