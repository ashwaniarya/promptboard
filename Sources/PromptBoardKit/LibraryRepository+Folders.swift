import Foundation

// Folder side of the library: create/rename/delete organizational directories under
// the prompts and skills trees, repointing any contained skill's symlinks on a move.
// Same discipline as LibraryRepository — self-locking RMW, atomic FS ops.
extension LibraryRepository {
    func treeRoot(for kind: LibraryEntry.Kind) -> URL {
        kind == .prompt ? promptsDirectoryURL : skillsDirectoryURL
    }

    // Validates a `/`-separated relative folder path (no empty/./.. components, not
    // absolute) and returns its absolute URL under the tree root. nil path == root.
    func folderURL(for kind: LibraryEntry.Kind, path: String?) throws -> URL {
        let root = treeRoot(for: kind)
        guard let path, !path.isEmpty else { return root }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"),
              !components.contains(""),
              !components.contains("."),
              !components.contains("..")
        else {
            throw LibraryRepositoryError.invalidSkillSource(path: path)
        }
        return root.appendingPathComponent(path, isDirectory: true)
    }

    public func createFolder(kind: LibraryEntry.Kind, path: String) throws {
        try withExclusiveLock {
            let url = try folderURL(for: kind, path: path)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: path)
            }
            try ensureDirectory(url)
        }
    }

    public func renameFolder(kind: LibraryEntry.Kind, from: String, to: String) throws {
        try withExclusiveLock {
            let oldURL = try folderURL(for: kind, path: from)
            let newURL = try folderURL(for: kind, path: to)
            guard FileManager.default.fileExists(atPath: oldURL.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: from)
            }
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: to)
            }
            // Record old skill-source paths (for symlink repoint) before the move.
            let movingSkills = kind == .skill ? skillFolderURLs().filter {
                $0.standardizedFileURL.path.hasPrefix(oldURL.standardizedFileURL.path + "/")
                    || $0.standardizedFileURL.path == oldURL.standardizedFileURL.path
            } : []
            try ensureDirectory(newURL.deletingLastPathComponent())
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            for oldSkillURL in movingSkills {
                let name = oldSkillURL.lastPathComponent
                let relativeSuffix = String(oldSkillURL.standardizedFileURL.path
                    .dropFirst(oldURL.standardizedFileURL.path.count))
                let newSkillURL = URL(fileURLWithPath: newURL.standardizedFileURL.path + relativeSuffix)
                SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: oldSkillURL)
                linkSkill(at: newSkillURL, name: name)
            }
        }
    }

    public func deleteFolder(kind: LibraryEntry.Kind, path: String) throws {
        try withExclusiveLock {
            let url = try folderURL(for: kind, path: path)
            guard url != treeRoot(for: kind),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: path)
            }
            let parent = url.deletingLastPathComponent()
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil
            )) ?? []
            for child in children {
                // Record skill sources under this child before moving it up.
                let movingSkills = kind == .skill ? skillFolderURLs().filter {
                    let skillPath = $0.standardizedFileURL.path
                    return skillPath == child.standardizedFileURL.path
                        || skillPath.hasPrefix(child.standardizedFileURL.path + "/")
                } : []
                let destination = uniqueDestination(for: child.lastPathComponent, in: parent)
                do {
                    try FileManager.default.moveItem(at: child, to: destination)
                } catch {
                    throw LibraryRepositoryError.ioFailure(underlying: error)
                }
                for oldSkillURL in movingSkills {
                    let name = oldSkillURL.lastPathComponent
                    let relativeSuffix = String(oldSkillURL.standardizedFileURL.path
                        .dropFirst(child.standardizedFileURL.path.count))
                    let newSkillURL = URL(fileURLWithPath: destination.standardizedFileURL.path + relativeSuffix)
                    SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: oldSkillURL)
                    linkSkill(at: newSkillURL, name: name)
                }
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
        }
    }

    public func movePrompt(id: UUID, toFolder folder: String?) throws {
        try withExclusiveLock {
            guard let found = try findPromptFile(id: id) else {
                throw LibraryRepositoryError.promptNotFound(id)
            }
            let destDir = try folderURL(for: .prompt, path: folder)
            // Already there → no-op. Both sides are directory URLs, so standardizedFileURL
            // (which does NOT normalize a trailing slash) compares them correctly; keep
            // destDir built with isDirectory:true and compare the file's parent, not the file.
            if found.url.deletingLastPathComponent().standardizedFileURL == destDir.standardizedFileURL {
                return
            }
            try ensureDirectory(destDir)
            let destination = uniqueDestination(for: found.url.lastPathComponent, in: destDir)
            do {
                try FileManager.default.moveItem(at: found.url, to: destination)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
        }
    }

    public func moveSkill(id: UUID, toFolder folder: String?) throws {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let name = found.url.lastPathComponent
            let destDir = try folderURL(for: .skill, path: folder)
            // Already there → no-op (return BEFORE unlink so the symlink is untouched).
            // Both sides are directory URLs; standardizedFileURL doesn't normalize a
            // trailing slash, so keep destDir built with isDirectory:true for this compare.
            if found.url.deletingLastPathComponent().standardizedFileURL == destDir.standardizedFileURL {
                return
            }
            try ensureDirectory(destDir)
            let destination = destDir.appendingPathComponent(name)
            // A skill's leaf folder name IS its flat symlink identity / slash-command
            // name — never auto-suffix it (unlike a prompt file); refuse the collision.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw LibraryRepositoryError.skillLinkConflict(name: name, path: destination.path)
            }
            SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: found.url)
            do {
                try FileManager.default.moveItem(at: found.url, to: destination)
            } catch {
                linkSkill(at: found.url, name: name)
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            linkSkill(at: destination, name: name)
        }
    }

    // Appends a numeric suffix if a same-named entry already exists in `directory`.
    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        let fileExtension = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixed = fileExtension.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(fileExtension)"
            candidate = directory.appendingPathComponent(suffixed)
            counter += 1
        }
        return candidate
    }

    private var folderMigrationMarkerURL: URL {
        libraryURL.appendingPathComponent(".promptboard-folders-v1")
    }

    // One-time: move each item whose legacy frontmatter/sidecar `group` is set into a
    // top-level folder of that name. Idempotent via a marker file. Reads the group
    // directly (readPrompt/readSkill now ignore it) so it can act before the marker.
    @discardableResult
    public func migrateGroupsToFoldersIfNeeded() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: folderMigrationMarkerURL.path) else { return false }
        return try withExclusiveLock {
            guard !FileManager.default.fileExists(atPath: folderMigrationMarkerURL.path) else { return false }

            for url in promptFileURLsForMigration() {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard let group = Frontmatter.parse(text).fields["group"], !group.isEmpty else { continue }
                guard Self.folderPath(of: url, underRoot: promptsDirectoryURL) == nil else { continue }
                guard let destDir = try? folderURL(for: .prompt, path: group) else {
                    logWarning("folder migration: skipping \"\(url.lastPathComponent)\" — invalid legacy group \"\(group)\"")
                    continue
                }
                try ensureDirectory(destDir)
                let destination = uniqueDestination(for: url.lastPathComponent, in: destDir)
                do {
                    try FileManager.default.moveItem(at: url, to: destination)
                } catch {
                    logWarning("folder migration: could not move \"\(url.lastPathComponent)\": \(error)")
                }
            }
            for folderURL in skillFolderURLs() {
                guard let group = readSidecar(in: folderURL)?.group, !group.isEmpty else { continue }
                guard Self.folderPath(of: folderURL, underRoot: skillsDirectoryURL) == nil else { continue }
                let name = folderURL.lastPathComponent
                guard let destDir = try? self.folderURL(for: .skill, path: group) else {
                    logWarning("folder migration: skipping skill \"\(name)\" — invalid legacy group \"\(group)\"")
                    continue
                }
                try ensureDirectory(destDir)
                let destination = destDir.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: folderURL)
                do {
                    try FileManager.default.moveItem(at: folderURL, to: destination)
                    linkSkill(at: destination, name: name)
                } catch {
                    // Move failed — restore the original link rather than leaving a
                    // dangling one; the item stays at root and migrates on no later run.
                    logWarning("folder migration: could not move skill \"\(name)\": \(error)")
                    linkSkill(at: folderURL, name: name)
                }
            }

            try Data("v1".utf8).write(to: folderMigrationMarkerURL, options: .atomic)
            return true
        }
    }

    // A flat, top-level list of prompt `.md` files for migration. Migration only moves
    // items still at the root (guarded by folderPath == nil), so a one-level scan suffices
    // and avoids re-visiting already-migrated files under new subfolders.
    private func promptFileURLsForMigration() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: promptsDirectoryURL, includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        return entries.filter {
            $0.pathExtension == "md"
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }
}
