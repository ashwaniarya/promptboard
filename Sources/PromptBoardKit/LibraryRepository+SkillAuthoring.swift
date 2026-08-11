import Foundation

// Authoring side of the folder library: create/edit skills and their files from
// inside the app. Same discipline as LibraryRepository — self-locking RMW, atomic
// writes, symlink no-clobber. Non-reentrant: never call these from inside `body`.
extension LibraryRepository {
    @discardableResult
    public func createSkill(name: String, description: String, group: String?, body: String) throws -> Skill {
        try withExclusiveLock {
            let folderName = Slug.unique(Slug.make(from: name), existing: existingSkillFolderNames())
            // group is a folder destination: file into skills/<group>/<folderName>/ (nil = root),
            // mirroring addPrompt(group:). The symlink stays flat (leaf name); sidecar group
            // stays nil since location is truth (load() derives group from the folder path).
            let destDir = try folderURL(for: .skill, path: group)
            try ensureDirectory(destDir)
            let destination = destDir.appendingPathComponent(folderName)
            try ensureDirectory(destination)
            try writeSkillMarkdown(name: folderName, description: description, body: body, in: destination)
            let now = Date()
            try writeSidecar(SkillSidecar(id: UUID(), group: nil, createdAt: now, updatedAt: now), in: destination)
            linkSkill(at: destination, name: folderName)
            guard let skill = readSkill(at: destination) else {
                throw LibraryRepositoryError.invalidSkillSource(path: destination.path)
            }
            return skill
        }
    }

    // Creates a skill from a prompt's content, then (optionally) removes the prompt.
    // Skill-first under one lock, so a mid-flow failure never loses the prompt.
    @discardableResult
    public func promotePromptToSkill(
        promptID: UUID, name: String, description: String, group: String?, removingPrompt: Bool
    ) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findPromptFile(id: promptID) else {
                throw LibraryRepositoryError.promptNotFound(promptID)
            }
            let folderName = Slug.unique(Slug.make(from: name), existing: existingSkillFolderNames())
            // group is a folder destination — file into skills/<group>/ (nil = root), as createSkill does.
            let destDir = try folderURL(for: .skill, path: group)
            try ensureDirectory(destDir)
            let destination = destDir.appendingPathComponent(folderName)
            try ensureDirectory(destination)
            try writeSkillMarkdown(name: folderName, description: description, body: found.prompt.content, in: destination)
            let now = Date()
            try writeSidecar(SkillSidecar(id: UUID(), group: nil, createdAt: now, updatedAt: now), in: destination)
            linkSkill(at: destination, name: folderName)
            if removingPrompt {
                do {
                    try FileManager.default.removeItem(at: found.url)
                } catch {
                    throw LibraryRepositoryError.ioFailure(underlying: error)
                }
            }
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

            // Resolve the final leaf name WITHOUT touching the filesystem yet.
            let desiredSlug = Slug.make(from: name)
            let effectiveName: String
            if desiredSlug != currentFolderName {
                effectiveName = Slug.unique(desiredSlug, existing: existingSkillFolderNames().subtracting([currentFolderName]))
            } else {
                effectiveName = currentFolderName
            }

            // Fail-fast BEFORE any mutation: if the final destination folder already holds
            // something named the final leaf (and it isn't this skill), refuse now.
            // existingSkillFolderNames() only counts skill leaves, so Slug.unique won't have
            // deduped against a plain org-folder — this guards the relocate below so the save
            // is all-or-nothing (no renamed-and-rewritten skill stranded on a late collision).
            let finalDestination = try self.folderURL(for: .skill, path: group).appendingPathComponent(effectiveName)
            if finalDestination.standardizedFileURL != found.url.standardizedFileURL,
               FileManager.default.fileExists(atPath: finalDestination.path) {
                throw LibraryRepositoryError.skillLinkConflict(name: effectiveName, path: finalDestination.path)
            }

            var currentSkillURL = found.url
            if effectiveName != currentFolderName {
                currentSkillURL = try renameSkillFolder(from: found.url, to: effectiveName)
            }

            try writeSkillMarkdown(name: effectiveName, description: description, body: body, in: currentSkillURL)
            let existing = readSidecar(in: currentSkillURL)
            try writeSidecar(SkillSidecar(
                id: found.skill.id,
                group: nil,
                createdAt: existing?.createdAt ?? found.skill.createdAt,
                updatedAt: Date()
            ), in: currentSkillURL)

            // Honour a group change on save: move the (possibly renamed) folder into the
            // `group` folder (nil = root). renameSkillFolder above targets the skills ROOT,
            // so a renamed-in-subfolder skill sits at root here; this pulls it into `group`.
            // The pre-check above guarantees this relocate can't hit a destination collision.
            let relocatedURL = try relocateSkillFolder(at: currentSkillURL, toFolder: group)

            guard var skill = readSkill(at: relocatedURL) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            // readSkill hardcodes group nil (location is truth); echo where it actually landed,
            // matching updatePrompt so callers see the destination folder.
            skill.group = Self.folderPath(of: relocatedURL, underRoot: skillsDirectoryURL)
            return skill
        }
    }

    // Renames a library skill folder and re-points its tool-directory symlinks.
    // The library namespace is ours, so the move can't collide; only the new symlink
    // path can be foreign — in which case the folder still renames and we warn.
    func renameSkillFolder(from oldURL: URL, to newFolderName: String) throws -> URL {
        let oldFolderName = oldURL.lastPathComponent
        let newURL = skillFolderURL(name: newFolderName)
        SymlinkManager.unlink(name: oldFolderName, from: syncTargets.all, expectedTarget: oldURL)
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
            group: nil,
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
        for directory in syncTargets.all {
            let linkURL = directory.appendingPathComponent(name)
            // Our own stale link — e.g. a prompt export the slug is being promoted over —
            // resolves inside storage but not at the new source. Repoint it silently, the
            // same way reconcile does; the alternative was a "not linked … isn't ours"
            // warning about a link that is, in fact, ours. Foreign entries (isOwned false)
            // are never removed and still surface the genuine no-clobber warning below.
            if SymlinkManager.isOwned(linkURL, byStorageRoot: directoryURL),
               SymlinkManager.resolvedDestination(of: linkURL)?.path != destination.standardizedFileURL.path {
                try? FileManager.default.removeItem(at: linkURL)
            }
            if SymlinkManager.link(source: destination, into: directory, name: name).conflicted {
                logWarning("skill \"\(name)\" not linked: \(linkURL.path) already exists and isn't ours")
            }
        }
    }
}
