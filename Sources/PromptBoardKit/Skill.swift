import Foundation

public struct SkillFile: Codable, Equatable, Hashable, Sendable {
    public let relativePath: String

    public init(relativePath: String) {
        self.relativePath = relativePath
    }
}

// A Claude Agent Skill: a folder whose SKILL.md carries the spec fields
// (`name`, `description`) plus a markdown body, alongside supporting files.
// PromptBoard's own bookkeeping (id, group, timestamps) lives in a sidecar so
// SKILL.md stays spec-pure — see LibraryRepository.
public struct Skill: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String
    public var group: String?
    public var body: String
    public var files: [SkillFile]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        group: String? = nil,
        body: String = "",
        files: [SkillFile] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.group = group
        self.body = body
        self.files = files
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
