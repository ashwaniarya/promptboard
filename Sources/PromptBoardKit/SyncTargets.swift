import Foundation

// ~/.agents/skills is read by Codex, Cursor and OpenCode; ~/.claude/skills by
// Claude Code, Cursor and OpenCode. Together they reach all four tools.
// No default initialiser value on purpose: a test that silently took one would
// write into the user's real tool directories.
public struct SyncTargets: Sendable, Equatable {
    public let claudeSkillsURL: URL
    public let agentsSkillsURL: URL

    public var all: [URL] { [agentsSkillsURL, claudeSkillsURL] }

    public init(claudeSkillsURL: URL, agentsSkillsURL: URL) {
        self.claudeSkillsURL = claudeSkillsURL
        self.agentsSkillsURL = agentsSkillsURL
    }

    public static func systemDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SyncTargets {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // A blank/whitespace-only override, or one still relative after ~ expansion,
        // resolves against the process's working directory instead of a real skills
        // folder, so it's treated as unset rather than honoured — these paths are used
        // to write symlinks into. Silently falling back to the user's *real* tool
        // directory would be worse than either: we warn so the miss is noticed.
        func directory(_ key: String, fallback: String) -> URL {
            let trimmed = environment[key]?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !trimmed.isEmpty else {
                return home.appendingPathComponent(fallback, isDirectory: true)
            }
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else {
                FileHandle.standardError.write(Data(
                    "PromptBoard: \(key)=\"\(trimmed)\" is not an absolute path, ignoring override\n".utf8
                ))
                return home.appendingPathComponent(fallback, isDirectory: true)
            }
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return SyncTargets(
            claudeSkillsURL: directory("PROMPTBOARD_CLAUDE_SKILLS_DIR", fallback: ".claude/skills"),
            agentsSkillsURL: directory("PROMPTBOARD_AGENTS_SKILLS_DIR", fallback: ".agents/skills")
        )
    }

    public static func temporary() -> SyncTargets {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptBoardSyncTargets-\(UUID().uuidString)", isDirectory: true)
        return SyncTargets(
            claudeSkillsURL: root.appendingPathComponent("claude", isDirectory: true),
            agentsSkillsURL: root.appendingPathComponent("agents", isDirectory: true)
        )
    }
}
