import Foundation

// Authoring side of the folder library: create/edit skills and their files from
// inside the app. Same discipline as LibraryRepository — self-locking RMW, atomic
// writes, symlink no-clobber. Non-reentrant: never call these from inside `body`.
extension LibraryRepository {
    @discardableResult
    public func createSkill(name: String, description: String, group: String?, body: String) throws -> Skill {
        try withExclusiveLock {
            let folderName = Slug.unique(Slug.make(from: name), existing: existingSkillFolderNames())
            try ensureDirectory(skillsDirectoryURL)
            let destination = skillFolderURL(name: folderName)
            try ensureDirectory(destination)
            try writeSkillMarkdown(name: folderName, description: description, body: body, in: destination)
            let now = Date()
            try writeSidecar(SkillSidecar(id: UUID(), group: group, createdAt: now, updatedAt: now), in: destination)
            linkSkill(at: destination, name: folderName)
            guard let skill = readSkill(at: destination) else {
                throw LibraryRepositoryError.invalidSkillSource(path: destination.path)
            }
            return skill
        }
    }

    // MARK: - Shared helpers

    func writeSkillMarkdown(name: String, description: String, body: String, in folderURL: URL) throws {
        let safeDescription = description
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let text = Frontmatter.render(fields: [("name", name), ("description", safeDescription)], body: body)
        do {
            try Data(text.utf8).write(to: folderURL.appendingPathComponent("SKILL.md"), options: .atomic)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }

    func linkSkill(at destination: URL, name: String) {
        let outcome = SymlinkManager.link(source: destination, into: claudeSkillsURL, name: name)
        if outcome.conflicted {
            logWarning("skill \"\(name)\" not linked: \(claudeSkillsURL.appendingPathComponent(name).path) already exists and isn't ours")
        }
    }
}
