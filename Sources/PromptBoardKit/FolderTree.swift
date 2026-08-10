import Foundation

// A node in the sidebar folder tree, built purely from items' derived `group` paths.
public struct FolderNode: Identifiable, Equatable, Sendable {
    public let name: String          // last path component, e.g. "ClientA"
    public let path: String          // full relative path, e.g. "Work/ClientA"
    public var children: [FolderNode]
    public var directCount: Int      // items whose group == this path
    public var subtreeCount: Int     // directCount + all descendants

    public var id: String { path }

    public static func build(from items: [LibraryEntry]) -> [FolderNode] {
        var directCounts: [String: Int] = [:]
        var allPaths = Set<String>()
        for item in items {
            guard let group = item.group, !group.isEmpty else { continue }
            directCounts[group, default: 0] += 1
            var parts = group.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                allPaths.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }
        func node(for path: String) -> FolderNode {
            let childPaths = allPaths.filter { candidate in
                candidate.hasPrefix(path + "/")
                    && !candidate.dropFirst(path.count + 1).contains("/")
            }
            let children = childPaths.sorted().map(node(for:))
            let direct = directCounts[path] ?? 0
            return FolderNode(
                name: String(path.split(separator: "/").last ?? ""),
                path: path,
                children: children,
                directCount: direct,
                subtreeCount: direct + children.reduce(0) { $0 + $1.subtreeCount }
            )
        }
        let topLevel = allPaths.filter { !$0.contains("/") }.sorted()
        return topLevel.map(node(for:))
    }
}
