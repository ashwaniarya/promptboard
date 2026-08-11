import Foundation

extension LibraryRepository {
    public struct SyncConflict: Sendable, Equatable {
        public let name: String
        public let reason: String
    }

    public var exportURL: URL { directoryURL.appendingPathComponent("Export", isDirectory: true) }
    public var exportSkillsURL: URL { exportURL.appendingPathComponent("skills", isDirectory: true) }

    // Regenerates the prompt exports, links every library item into both target
    // directories, and prunes links we own whose source has gone. Idempotent.
    @discardableResult
    public func reconcileSync() throws -> [SyncConflict] {
        let load = try load()
        var conflicts: [SyncConflict] = []

        // Folder names are the on-disk truth. `Skill.name` comes from SKILL.md and
        // can differ from its folder (collision suffixes, hand edits), so enumerate.
        // Recursive: a skill may live at any depth; its symlink name is the leaf name.
        var skillNames = Set<String>()
        var sources: [String: URL] = [:]
        for folder in skillFolderURLs() {
            let name = folder.lastPathComponent
            skillNames.insert(name)
            sources[name] = folder
        }

        try ensureDirectory(exportSkillsURL)
        var exportedNames = Set<String>()
        for case .prompt(let prompt) in load.items {
            let export = SkillExportRenderer.render(prompt)
            guard !skillNames.contains(export.folderName) else {
                conflicts.append(SyncConflict(
                    name: export.folderName,
                    reason: "a skill already uses this name — rename the prompt"
                ))
                continue
            }
            // Two prompts whose titles slugify to the same name would otherwise
            // overwrite each other's export last-writer-wins, silently dropping one
            // from every tool. Report it instead — auto-suffixing the slash-command
            // name a user types is exactly what the design rejects.
            guard !exportedNames.contains(export.folderName) else {
                conflicts.append(SyncConflict(
                    name: export.folderName,
                    reason: "another prompt already uses this slash-command name — rename one"
                ))
                continue
            }
            let folder = exportSkillsURL.appendingPathComponent(export.folderName, isDirectory: true)
            try ensureDirectory(folder.appendingPathComponent("agents", isDirectory: true))
            try Data(export.skillMarkdown.utf8)
                .write(to: folder.appendingPathComponent("SKILL.md"), options: .atomic)
            try Data(export.openAIPolicy.utf8)
                .write(to: folder.appendingPathComponent("agents/openai.yaml"), options: .atomic)
            exportedNames.insert(export.folderName)
            sources[export.folderName] = folder
        }

        for name in existingExportNames() where !exportedNames.contains(name) {
            try? FileManager.default.removeItem(at: exportSkillsURL.appendingPathComponent(name))
        }

        for (name, source) in sources {
            for directory in syncTargets.all {
                let linkURL = directory.appendingPathComponent(name)
                // Repoint our own stale link before linking: a slug that moved from a
                // prompt export to an authored skill (or the reverse) leaves an owned
                // link aimed at the vanished source. Foreign entries stay untouched —
                // isOwned is false for a real folder or a link resolving outside storage.
                if SymlinkManager.isOwned(linkURL, byStorageRoot: directoryURL),
                   SymlinkManager.resolvedDestination(of: linkURL)?.path != source.standardizedFileURL.path {
                    try? FileManager.default.removeItem(at: linkURL)
                }
                if SymlinkManager.link(source: source, into: directory, name: name).conflicted {
                    conflicts.append(SyncConflict(name: name, reason: "a foreign entry already occupies this path"))
                }
            }
        }

        pruneStaleLinks(keeping: Set(sources.keys))
        return conflicts
    }

    private func existingExportNames() -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: exportSkillsURL, includingPropertiesForKeys: nil
        )
        return (contents ?? []).map(\.lastPathComponent)
    }

    private func pruneStaleLinks(keeping names: Set<String>) {
        for directory in syncTargets.all {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            for entry in contents where SymlinkManager.isOwned(entry, byStorageRoot: directoryURL) {
                guard !names.contains(entry.lastPathComponent) else { continue }
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
