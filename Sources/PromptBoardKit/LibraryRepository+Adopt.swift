import Foundation

extension LibraryRepository {
    public enum AdoptMode: Sendable, Equatable {
        case move
        case copy
    }

    // Move leaves a link at the original path so a tool that reads only its own
    // directory keeps working; reconcile then links the item into both targets.
    // Adoption goes through createSkill/addPrompt rather than a raw folder copy so
    // the `.promptboard.json` sidecar is written by the same code that owns it.
    public func adoptExternal(_ item: ExternalItem, mode: AdoptMode) throws {
        switch item.kind {
        case .skill:
            try adoptSkill(item, mode: mode)
        case .prompt:
            try adoptPrompt(item, mode: mode)
        }
    }

    private func adoptSkill(_ item: ExternalItem, mode: AdoptMode) throws {
        let folderName = Slug.make(from: item.name)
        let destination = skillsDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LibraryRepositoryError.skillLinkConflict(name: folderName, path: destination.path)
        }

        let text = (try? String(contentsOf: item.url.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let document = Frontmatter.parse(text)
        // The free-destination guard plus Slug.make being idempotent on an already-
        // slugged name means createSkill lands exactly at `destination`.
        let skill = try createSkill(
            name: folderName,
            description: document.fields["description"] ?? "",
            group: nil,
            body: document.body
        )

        // Standardize both sides before diffing: the enumerator yields the symlink-
        // resolved form (e.g. /private/var vs /var), so a plain string strip of the
        // prefix would leave a `/private…` scrap and mislabel even SKILL.md itself.
        let basePath = item.url.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(basePath + "/") else { continue }
            let relative = String(path.dropFirst(basePath.count + 1))
            guard relative != "SKILL.md", relative != ".promptboard.json", !relative.hasPrefix("."),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: file)
            else { continue }
            _ = try writeSkillFile(id: skill.id, relativePath: relative, data: data)
        }

        if mode == .move {
            try backUpAndReplaceWithLink(original: item.url, target: destination)
        }
        _ = try reconcileSync()
    }

    private func adoptPrompt(_ item: ExternalItem, mode: AdoptMode) throws {
        let text = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
        let document = Frontmatter.parse(text)
        let prompt = try addPrompt(title: item.name, content: document.body, group: nil)

        if mode == .move {
            // addPrompt may normalize the title and de-dup the slug, so the file need
            // not sit at `Slug.make(prompt.title).md`. Link to the file it actually
            // wrote, read back from disk, or the move leaves a dangling (or wrong) link.
            guard let created = try findPromptFile(id: prompt.id) else {
                throw LibraryRepositoryError.promptNotFound(prompt.id)
            }
            try backUpAndReplaceWithLink(original: item.url, target: created.url)
        }
        _ = try reconcileSync()
    }

    private func backUpAndReplaceWithLink(original: URL, target: URL) throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = original.deletingLastPathComponent()
            .appendingPathComponent("\(original.lastPathComponent).promptboard-backup-\(stamp)")
        try FileManager.default.moveItem(at: original, to: backup)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)
    }
}
