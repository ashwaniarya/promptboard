import Foundation

public struct ClipboardHistory: Equatable, Sendable {
    public static let capacity = 50
    public private(set) var items: [String] = []

    public init() {}

    public mutating func record(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    public func matches(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
