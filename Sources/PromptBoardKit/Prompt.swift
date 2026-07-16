import Foundation

public struct Prompt: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
