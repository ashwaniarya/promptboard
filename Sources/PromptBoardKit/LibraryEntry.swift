import Foundation

public enum LibraryEntry: Identifiable, Equatable, Sendable {
    case prompt(Prompt)
    case skill(Skill)
    case chain(Chain)

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case prompt
        case skill
        case chain
    }

    public var id: UUID {
        switch self {
        case .prompt(let prompt): prompt.id
        case .skill(let skill): skill.id
        case .chain(let chain): chain.id
        }
    }

    public var kind: Kind {
        switch self {
        case .prompt: .prompt
        case .skill: .skill
        case .chain: .chain
        }
    }

    public var title: String {
        switch self {
        case .prompt(let prompt): prompt.title
        case .skill(let skill): skill.name
        case .chain(let chain): chain.title
        }
    }

    public var group: String? {
        switch self {
        case .prompt(let prompt): prompt.group
        case .skill(let skill): skill.group
        case .chain(let chain): chain.group
        }
    }

    public var updatedAt: Date {
        switch self {
        case .prompt(let prompt): prompt.updatedAt
        case .skill(let skill): skill.updatedAt
        case .chain(let chain): chain.updatedAt
        }
    }

    public var previewText: String {
        switch self {
        case .prompt(let prompt): prompt.content
        case .skill(let skill): skill.description.isEmpty ? skill.body : skill.description
        case .chain(let chain): "\(chain.steps.count) steps"
        }
    }
}

// Encodes as the item's own fields plus a `kind` discriminator, so `list --json`
// and MCP payloads are flat, self-describing objects.
extension LibraryEntry: Codable {
    private enum DiscriminatorKeys: String, CodingKey { case kind }

    public init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: DiscriminatorKeys.self).decode(Kind.self, forKey: .kind)
        switch kind {
        case .prompt: self = .prompt(try Prompt(from: decoder))
        case .skill: self = .skill(try Skill(from: decoder))
        case .chain: self = .chain(try Chain(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .prompt(let prompt): try prompt.encode(to: encoder)
        case .skill(let skill): try skill.encode(to: encoder)
        case .chain(let chain): try chain.encode(to: encoder)
        }
        var container = encoder.container(keyedBy: DiscriminatorKeys.self)
        try container.encode(kind, forKey: .kind)
    }
}
