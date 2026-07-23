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

    @discardableResult
    public func updateSkill(id: UUID, name: String, description: String, group: String?, body: String) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let currentFolderName = found.url.lastPathComponent
            var folderURL = found.url
            var effectiveName = currentFolderName

            let desiredSlug = Slug.make(from: name)
            if desiredSlug != currentFolderName {
                let others = existingSkillFolderNames().subtracting([currentFolderName])
                let newFolderName = Slug.unique(desiredSlug, existing: others)
                folderURL = try renameSkillFolder(from: found.url, to: newFolderName)
                effectiveName = newFolderName
            }

            try writeSkillMarkdown(name: effectiveName, description: description, body: body, in: folderURL)
            let existing = readSidecar(in: folderURL)
            try writeSidecar(SkillSidecar(
                id: found.skill.id,
                group: group,
                createdAt: existing?.createdAt ?? found.skill.createdAt,
                updatedAt: Date()
            ), in: folderURL)

            guard let skill = readSkill(at: folderURL) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            return skill
        }
    }

    // Renames a library skill folder and re-points its ~/.claude/skills symlink.
    // The library namespace is ours, so the move can't collide; only the new symlink
    // path can be foreign — in which case the folder still renames and we warn.
    func renameSkillFolder(from oldURL: URL, to newFolderName: String) throws -> URL {
        let oldFolderName = oldURL.lastPathComponent
        let newURL = skillFolderURL(name: newFolderName)
        SymlinkManager.unlink(name: oldFolderName, from: claudeSkillsURL, expectedTarget: oldURL)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            linkSkill(at: oldURL, name: oldFolderName)
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
        linkSkill(at: newURL, name: newFolderName)
        return newURL
    }

    // MARK: - Skill file ops

    @discardableResult
    public func writeSkillFile(id: UUID, relativePath: String, data: Data) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let fileURL = try validatedSkillFileURL(in: found.url, relativePath: relativePath)
            try ensureDirectory(fileURL.deletingLastPathComponent())
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return try touchAndReadSkill(id: id, in: found.url, skill: found.skill)
        }
    }

    @discardableResult
    public func renameSkillFile(id: UUID, from source: String, to destination: String) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let sourceURL = try validatedSkillFileURL(in: found.url, relativePath: source)
            let destinationURL = try validatedSkillFileURL(in: found.url, relativePath: destination)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: source)
            }
            try ensureDirectory(destinationURL.deletingLastPathComponent())
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return try touchAndReadSkill(id: id, in: found.url, skill: found.skill)
        }
    }

    @discardableResult
    public func deleteSkillFile(id: UUID, relativePath: String) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let fileURL = try validatedSkillFileURL(in: found.url, relativePath: relativePath)
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return try touchAndReadSkill(id: id, in: found.url, skill: found.skill)
        }
    }

    // Rejects empty paths, the two managed files, and anything escaping the folder.
    // Purely lexical (no stat/symlink resolution) so it holds for files not yet on disk.
    func validatedSkillFileURL(in folderURL: URL, relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespaces)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !trimmed.isEmpty,
              trimmed != "SKILL.md",
              trimmed != ".promptboard.json",
              !trimmed.hasPrefix("/"),
              !components.contains(""),
              !components.contains("."),
              !components.contains("..")
        else {
            throw LibraryRepositoryError.invalidSkillSource(path: relativePath)
        }
        return folderURL.appendingPathComponent(trimmed)
    }

    func touchAndReadSkill(id: UUID, in folderURL: URL, skill: Skill) throws -> Skill {
        let existing = readSidecar(in: folderURL)
        try writeSidecar(SkillSidecar(
            id: skill.id,
            group: existing?.group ?? skill.group,
            createdAt: existing?.createdAt ?? skill.createdAt,
            updatedAt: Date()
        ), in: folderURL)
        guard let refreshed = readSkill(at: folderURL) else {
            throw LibraryRepositoryError.skillNotFound(id)
        }
        return refreshed
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
