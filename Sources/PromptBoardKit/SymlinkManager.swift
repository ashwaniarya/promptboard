import Foundation

// Manages ~/.claude/skills/<name> symlinks with a strict no-clobber rule: we only
// ever create, verify, or remove links that point into our own library. Anything
// else already at that path (a real folder, a foreign symlink) is left untouched.
enum SymlinkManager {
    struct Outcome: Sendable {
        let name: String
        let linked: Bool
        let conflicted: Bool
    }

    @discardableResult
    static func link(source: URL, into skillsDirectory: URL, name: String) -> Outcome {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        let linkURL = skillsDirectory.appendingPathComponent(name)

        if let target = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) {
            let resolved = URL(fileURLWithPath: target, relativeTo: linkURL).standardizedFileURL
            if resolved.path == source.standardizedFileURL.path {
                return Outcome(name: name, linked: true, conflicted: false)
            }
            return Outcome(name: name, linked: false, conflicted: true)
        }
        if fileManager.fileExists(atPath: linkURL.path) {
            return Outcome(name: name, linked: false, conflicted: true)
        }
        do {
            try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: source)
            return Outcome(name: name, linked: true, conflicted: false)
        } catch {
            return Outcome(name: name, linked: false, conflicted: false)
        }
    }

    static func unlink(name: String, from skillsDirectory: URL, expectedTarget: URL) {
        let fileManager = FileManager.default
        let linkURL = skillsDirectory.appendingPathComponent(name)
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) else { return }
        let resolved = URL(fileURLWithPath: target, relativeTo: linkURL).standardizedFileURL
        guard resolved.path == expectedTarget.standardizedFileURL.path else { return }
        try? fileManager.removeItem(at: linkURL)
    }
}
