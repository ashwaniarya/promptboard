import Foundation

public enum LibraryEntry: Identifiable, Equatable, Sendable {
    case prompt(Prompt)
    case skill(Skill)

    public enum Kind: String, Sendable, CaseIterable {
        case prompt
        case skill
    }

    public var id: UUID {
        switch self {
        case .prompt(let prompt): prompt.id
        case .skill(let skill): skill.id
        }
    }

    public var kind: Kind {
        switch self {
        case .prompt: .prompt
        case .skill: .skill
        }
    }

    public var title: String {
        switch self {
        case .prompt(let prompt): prompt.title
        case .skill(let skill): skill.name
        }
    }

    public var group: String? {
        switch self {
        case .prompt(let prompt): prompt.group
        case .skill(let skill): skill.group
        }
    }

    public var updatedAt: Date {
        switch self {
        case .prompt(let prompt): prompt.updatedAt
        case .skill(let skill): skill.updatedAt
        }
    }

    public var previewText: String {
        switch self {
        case .prompt(let prompt): prompt.content
        case .skill(let skill): skill.description.isEmpty ? skill.body : skill.description
        }
    }
}
