import Foundation

// A node in the sidebar folder tree. Built from items' derived `group` paths, unioned
// with `extraFolderPaths` — on-disk folders that hold no items yet, so a freshly created
// (empty) folder still shows in the sidebar as a directCount-0 node.
public struct FolderNode: Identifiable, Equatable, Sendable {
    public let name: String          // last path component, e.g. "ClientA"
    public let path: String          // full relative path, e.g. "Work/ClientA"
    public var children: [FolderNode]
    public var directCount: Int      // items whose group == this path
    public var subtreeCount: Int     // directCount + all descendants

    public var id: String { path }

    public static func build(from items: [LibraryEntry], extraFolderPaths: [String] = []) -> [FolderNode] {
        var directCounts: [String: Int] = [:]
        var allPaths = Set<String>()

        // Insert a path and every ancestor, so a deep group materializes its parents.
        func insertWithAncestors(_ path: String) {
            var parts = path.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                allPaths.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }

        for item in items {
            guard let group = item.group, !group.isEmpty else { continue }
            let parts = group.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }
            // Key on the normalized join, so counts and structure share one canonical key
            // even if a group ever carried a stray/doubled slash.
            directCounts[parts.joined(separator: "/"), default: 0] += 1
            insertWithAncestors(group)
        }
        for path in extraFolderPaths where !path.isEmpty {
            insertWithAncestors(path)
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
