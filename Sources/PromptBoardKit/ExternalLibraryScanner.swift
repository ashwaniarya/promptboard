import Foundation

public struct ExternalItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case skill
        case prompt
    }

    public var id: String { url.path }
    public let name: String
    public let kind: Kind
    public let origin: String
    public let url: URL
    public let description: String

    public init(name: String, kind: Kind, origin: String, url: URL, description: String = "") {
        self.name = name
        self.kind = kind
        self.origin = origin
        self.url = url
        self.description = description
    }
}

// Read-only discovery of skills and commands that already live inside each tool.
// Cursor's managed `skills-cursor` is absent from the root table on purpose (it
// reverts hand edits), and Codex's `.system` cache is caught by the dot-entry rule.
public enum ExternalLibraryScanner {
    public struct Root: Sendable, Equatable {
        public let url: URL
        public let origin: String
        public let kind: ExternalItem.Kind

        public init(url: URL, origin: String, kind: ExternalItem.Kind) {
            self.url = url
            self.origin = origin
            self.kind = kind
        }
    }

    public static func defaultRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [Root] {
        if let raw = environment["PROMPTBOARD_EXTERNAL_SCAN_ROOTS"], !raw.isEmpty {
            return raw.split(separator: ":").map {
                Root(url: URL(fileURLWithPath: String($0), isDirectory: true), origin: "External", kind: .skill)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        func url(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: true) }
        return [
            Root(url: url(".claude/skills"), origin: "Claude Code", kind: .skill),
            Root(url: url(".claude/commands"), origin: "Claude Code", kind: .prompt),
            Root(url: url(".agents/skills"), origin: "Agents", kind: .skill),
            Root(url: url(".codex/skills"), origin: "Codex", kind: .skill),
            Root(url: url(".cursor/skills"), origin: "Cursor", kind: .skill),
            Root(url: url(".config/opencode/skill"), origin: "OpenCode", kind: .skill),
            Root(url: url(".config/opencode/skills"), origin: "OpenCode", kind: .skill),
            Root(url: url(".config/opencode/command"), origin: "OpenCode", kind: .prompt),
            Root(url: url(".config/opencode/commands"), origin: "OpenCode", kind: .prompt),
        ]
    }

    public static func scan(roots: [Root], storageRoot: URL) -> [ExternalItem] {
        var items: [ExternalItem] = []
        for root in roots {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: root.url, includingPropertiesForKeys: nil
            )) ?? []
            for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = entry.lastPathComponent
                guard !name.hasPrefix("."),
                      !SymlinkManager.isOwned(entry, byStorageRoot: storageRoot) else { continue }
                switch root.kind {
                case .skill:
                    let skillFile = entry.appendingPathComponent("SKILL.md")
                    guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
                    items.append(ExternalItem(
                        name: name, kind: .skill, origin: root.origin, url: entry,
                        description: descriptionFromFrontmatter(at: skillFile)
                    ))
                case .prompt:
                    // A directory named "foo.md" matches the extension check but is not a
                    // prompt file — surfacing it would make Task 7's adopt read a folder
                    // as file content. Require a regular file.
                    let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    guard entry.pathExtension == "md", !isDirectory else { continue }
                    items.append(ExternalItem(
                        name: entry.deletingPathExtension().lastPathComponent,
                        kind: .prompt, origin: root.origin, url: entry,
                        description: descriptionFromFrontmatter(at: entry)
                    ))
                }
            }
        }
        return items
    }

    // A one-line preview for the card: the frontmatter `description` if present, else the
    // first non-empty body line. Bounded and single-line so a card stays compact.
    private static func descriptionFromFrontmatter(at url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let document = Frontmatter.parse(text)
        let raw = document.fields["description"]
            ?? document.body.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(String.init)
            ?? ""
        let flattened = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flattened.prefix(200))
    }
}
