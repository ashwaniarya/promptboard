import Foundation

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
                let relative = String(oldSkillURL.standardizedFileURL.path
                    .dropFirst(oldURL.standardizedFileURL.path.count))
                let newSkillURL = URL(fileURLWithPath: newURL.standardizedFileURL.path + relative)
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
                    let p = $0.standardizedFileURL.path
                    return p == child.standardizedFileURL.path
                        || p.hasPrefix(child.standardizedFileURL.path + "/")
                } : []
                let destination = uniqueDestination(for: child.lastPathComponent, in: parent)
                try FileManager.default.moveItem(at: child, to: destination)
                for oldSkillURL in movingSkills {
                    let name = oldSkillURL.lastPathComponent
                    let relative = String(oldSkillURL.standardizedFileURL.path
                        .dropFirst(child.standardizedFileURL.path.count))
                    let newSkillURL = URL(fileURLWithPath: destination.standardizedFileURL.path + relative)
                    SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: oldSkillURL)
                    linkSkill(at: newSkillURL, name: name)
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // Appends a numeric suffix if a same-named entry already exists in `directory`.
    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixed = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(suffixed)
            counter += 1
        }
        return candidate
    }
}
