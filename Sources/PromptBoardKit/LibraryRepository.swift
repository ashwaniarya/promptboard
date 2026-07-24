import Foundation

public enum LibraryRepositoryError: Error, Sendable {
    case promptNotFound(UUID)
    case skillNotFound(UUID)
    case nothingToUpdate
    case lockTimeout(path: String)
    case ioFailure(underlying: any Error)
    case skillLinkConflict(name: String, path: String)
    case invalidSkillSource(path: String)
}

// Folder-based library: prompts as `<slug>.md` (frontmatter + body), skills as
// Agent Skills folders with a `.promptboard.json` sidecar. flock read-modify-write
// with atomic per-file writes, now spanning many files instead of one JSON blob.
// Non-reentrant: never call the self-locking conveniences from inside `body`.
public struct LibraryRepository: Sendable {
    public let directoryURL: URL
    public let syncTargets: SyncTargets

    public var claudeSkillsURL: URL { syncTargets.claudeSkillsURL }

    public var libraryURL: URL { directoryURL.appendingPathComponent("Library", isDirectory: true) }
    public var promptsDirectoryURL: URL { libraryURL.appendingPathComponent("prompts", isDirectory: true) }
    public var skillsDirectoryURL: URL { libraryURL.appendingPathComponent("skills", isDirectory: true) }
    private var lockFileURL: URL { libraryURL.appendingPathComponent(".promptboard.lock") }
    private var legacyDataFileURL: URL { directoryURL.appendingPathComponent("prompts.json") }

    public static var defaultDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptBoard", isDirectory: true)
    }

    public init(directoryURL: URL, syncTargets: SyncTargets) {
        self.directoryURL = directoryURL
        self.syncTargets = syncTargets
    }

    // MARK: - Loading

    public struct Load: Sendable {
        public let items: [LibraryEntry]
        public let skippedPaths: [String]

        public init(items: [LibraryEntry], skippedPaths: [String]) {
            self.items = items
            self.skippedPaths = skippedPaths
        }
    }

    // Lock-free: each file is written atomically, so a scan never sees a torn item.
    public func load() throws -> Load {
        var items: [LibraryEntry] = []
        var skipped: [String] = []
        for url in promptFileURLs() {
            if let prompt = readPrompt(at: url) {
                items.append(.prompt(prompt))
            } else {
                skipped.append(url.path)
            }
        }
        for folderURL in skillFolderURLs() {
            if let skill = readSkill(at: folderURL) {
                items.append(.skill(skill))
            } else {
                skipped.append(folderURL.path)
            }
        }
        return Load(items: items, skippedPaths: skipped)
    }

    // MARK: - Prompt CRUD

    @discardableResult
    public func addPrompt(title: String, content: String, group: String? = nil) throws -> Prompt {
        try withExclusiveLock {
            try ensureDirectory(promptsDirectoryURL)
            let normalized = Self.normalizedTitle(title)
            let slug = Slug.unique(Slug.make(from: normalized), existing: existingPromptSlugs())
            let prompt = Prompt(title: normalized, content: content, group: group)
            try writePrompt(prompt, to: promptsDirectoryURL.appendingPathComponent("\(slug).md"))
            return prompt
        }
    }

    // group == nil keeps the existing group; clearing a group is deferred to Layer B.
    @discardableResult
    public func updatePrompt(id: UUID, title: String?, content: String?, group: String? = nil) throws -> Prompt {
        guard title != nil || content != nil || group != nil else {
            throw LibraryRepositoryError.nothingToUpdate
        }
        return try withExclusiveLock {
            guard let found = try findPromptFile(id: id) else {
                throw LibraryRepositoryError.promptNotFound(id)
            }
            var prompt = found.prompt
            if let title { prompt.title = Self.normalizedTitle(title) }
            if let content { prompt.content = content }
            if let group { prompt.group = group }
            prompt.updatedAt = Date()
            try writePrompt(prompt, to: found.url)
            return prompt
        }
    }

    @discardableResult
    public func deletePrompt(id: UUID) throws -> Prompt {
        try withExclusiveLock {
            guard let found = try findPromptFile(id: id) else {
                throw LibraryRepositoryError.promptNotFound(id)
            }
            do {
                try FileManager.default.removeItem(at: found.url)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return found.prompt
        }
    }

    // MARK: - Migration

    // Idempotent one-time migration of the legacy prompts.json into the folder library.
    // Aborts (leaving prompts.json intact) on any error; refuses to merge into a populated
    // library so a partial state can't double up.
    @discardableResult
    public func migrateLegacyIfNeeded() throws -> Bool {
        // Unlocked fast path: with no legacy file there is nothing to do, and we must
        // not create the library dir (a read-only `list` on an empty dir stays inert).
        guard FileManager.default.fileExists(atPath: legacyDataFileURL.path) else { return false }
        return try withExclusiveLock {
            guard FileManager.default.fileExists(atPath: legacyDataFileURL.path) else { return false }
            guard existingPromptSlugs().isEmpty else { return false }

            let data: Data
            do {
                data = try Data(contentsOf: legacyDataFileURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            let prompts: [Prompt]
            do {
                prompts = try CanonicalJSON.makeDecoder().decode([Prompt].self, from: data)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }

            try ensureDirectory(promptsDirectoryURL)
            var used = Set<String>()
            for prompt in prompts {
                let slug = Slug.unique(Slug.make(from: prompt.title), existing: used)
                used.insert(slug)
                try writePrompt(prompt, to: promptsDirectoryURL.appendingPathComponent("\(slug).md"))
            }
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directoryURL.appendingPathComponent("prompts.json.migrated-\(stamp)")
            do {
                try FileManager.default.moveItem(at: legacyDataFileURL, to: backup)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return true
        }
    }

    public func ensureLibraryDirectories() throws {
        try ensureDirectory(promptsDirectoryURL)
        try ensureDirectory(skillsDirectoryURL)
    }

    // Seeds sample prompts only into an empty library; the existence re-check inside
    // the lock makes concurrent first-run stores race-safe (no double seed).
    @discardableResult
    public func seedPromptsIfEmpty(_ samples: [Prompt]) throws -> Bool {
        try withExclusiveLock {
            guard existingPromptSlugs().isEmpty else { return false }
            try ensureDirectory(promptsDirectoryURL)
            var used = Set<String>()
            for sample in samples {
                let slug = Slug.unique(Slug.make(from: sample.title), existing: used)
                used.insert(slug)
                try writePrompt(sample, to: promptsDirectoryURL.appendingPathComponent("\(slug).md"))
            }
            return true
        }
    }

    // MARK: - Internals

    static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func promptFileURLs() -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: promptsDirectoryURL, includingPropertiesForKeys: nil
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func existingPromptSlugs() -> Set<String> {
        Set(promptFileURLs().map { $0.deletingPathExtension().lastPathComponent })
    }

    func findPromptFile(id: UUID) throws -> (url: URL, prompt: Prompt)? {
        for url in promptFileURLs() {
            if let prompt = readPrompt(at: url), prompt.id == id {
                return (url, prompt)
            }
        }
        return nil
    }

    private func readPrompt(at url: URL) -> Prompt? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let doc = Frontmatter.parse(text)
        guard let idString = doc.fields["id"], let id = UUID(uuidString: idString) else { return nil }
        let created = doc.fields["createdAt"].flatMap(CanonicalJSON.date(from:)) ?? Date()
        let updated = doc.fields["updatedAt"].flatMap(CanonicalJSON.date(from:)) ?? created
        return Prompt(
            id: id,
            title: doc.fields["title"] ?? "Untitled",
            content: doc.body,
            group: doc.fields["group"],
            createdAt: created,
            updatedAt: updated
        )
    }

    private func writePrompt(_ prompt: Prompt, to url: URL) throws {
        var fields: [(String, String)] = [
            ("id", prompt.id.uuidString),
            ("title", prompt.title),
        ]
        if let group = prompt.group {
            fields.append(("group", group))
        }
        fields.append(("createdAt", CanonicalJSON.isoString(from: prompt.createdAt)))
        fields.append(("updatedAt", CanonicalJSON.isoString(from: prompt.updatedAt)))
        let text = Frontmatter.render(fields: fields, body: prompt.content)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }

    func ensureDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }

    // Locks a sidecar file (stable inode) because atomic writes replace item files.
    func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try ensureDirectory(libraryURL)
        let lockDescriptor = open(lockFileURL.path, O_CREAT | O_WRONLY | O_CLOEXEC, 0o644)
        guard lockDescriptor >= 0 else {
            throw LibraryRepositoryError.ioFailure(
                underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            )
        }
        defer { close(lockDescriptor) }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else {
                throw LibraryRepositoryError.lockTimeout(path: lockFileURL.path)
            }
            usleep(20_000)
        }
        return try body()
    }
}

struct SkillSidecar: Codable, Sendable {
    var id: UUID
    var group: String?
    var createdAt: Date
    var updatedAt: Date
}

extension LibraryRepository {
    // MARK: - Skill CRUD

    @discardableResult
    public func importSkill(fromDirectory source: URL, group: String? = nil) throws -> Skill {
        try withExclusiveLock {
            let sourceSkillFile = source.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: sourceSkillFile, encoding: .utf8) else {
                throw LibraryRepositoryError.invalidSkillSource(path: source.path)
            }
            let declaredName = Frontmatter.parse(text).fields["name"] ?? source.lastPathComponent
            let folderName = Slug.unique(Slug.make(from: declaredName), existing: existingSkillFolderNames())
            try ensureDirectory(skillsDirectoryURL)
            let destination = skillFolderURL(name: folderName)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            let now = Date()
            try writeSidecar(SkillSidecar(id: UUID(), group: group, createdAt: now, updatedAt: now), in: destination)
            let outcome = SymlinkManager.link(source: destination, into: claudeSkillsURL, name: folderName)
            if outcome.conflicted {
                logWarning("skill \"\(folderName)\" not linked: \(claudeSkillsURL.appendingPathComponent(folderName).path) already exists and isn't ours")
            }
            guard let skill = readSkill(at: destination) else {
                throw LibraryRepositoryError.invalidSkillSource(path: destination.path)
            }
            return skill
        }
    }

    @discardableResult
    public func updateSkillGroup(id: UUID, group: String?) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            var sidecar = readSidecar(in: found.url) ?? SkillSidecar(
                id: found.skill.id, group: nil,
                createdAt: found.skill.createdAt, updatedAt: found.skill.updatedAt
            )
            sidecar.group = group
            sidecar.updatedAt = Date()
            try writeSidecar(sidecar, in: found.url)
            guard let skill = readSkill(at: found.url) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            return skill
        }
    }

    @discardableResult
    public func deleteSkill(id: UUID) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            SymlinkManager.unlink(
                name: found.url.lastPathComponent, from: claudeSkillsURL, expectedTarget: found.url
            )
            do {
                try FileManager.default.removeItem(at: found.url)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return found.skill
        }
    }

    // Re-establish symlinks for every library skill (idempotent, no-clobber).
    @discardableResult
    public func relinkAllSkills() throws -> Int {
        try withExclusiveLock {
            skillFolderURLs().reduce(into: 0) { linked, folderURL in
                let outcome = SymlinkManager.link(
                    source: folderURL, into: claudeSkillsURL, name: folderURL.lastPathComponent
                )
                if outcome.linked { linked += 1 }
            }
        }
    }

    // MARK: - Skill internals

    func skillFolderURL(name: String) -> URL {
        skillsDirectoryURL.appendingPathComponent(name)
    }

    func skillFolderURLs() -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: skillsDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func existingSkillFolderNames() -> Set<String> {
        Set(skillFolderURLs().map { $0.lastPathComponent })
    }

    func findSkillFolder(id: UUID) throws -> (url: URL, skill: Skill)? {
        for folderURL in skillFolderURLs() {
            if let skill = readSkill(at: folderURL), skill.id == id {
                return (folderURL, skill)
            }
        }
        return nil
    }

    func readSkill(at folderURL: URL) -> Skill? {
        let skillFile = folderURL.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let doc = Frontmatter.parse(text)
        let sidecar = readSidecar(in: folderURL)
        let created = sidecar?.createdAt ?? folderCreationDate(folderURL) ?? Date()
        return Skill(
            id: sidecar?.id ?? Self.stableSkillID(forName: folderURL.lastPathComponent),
            name: doc.fields["name"] ?? folderURL.lastPathComponent,
            description: doc.fields["description"] ?? "",
            group: sidecar?.group,
            body: doc.body,
            files: supportingFiles(in: folderURL),
            createdAt: created,
            updatedAt: sidecar?.updatedAt ?? created
        )
    }

    func readSidecar(in folderURL: URL) -> SkillSidecar? {
        guard let data = try? Data(contentsOf: folderURL.appendingPathComponent(".promptboard.json")) else {
            return nil
        }
        return try? CanonicalJSON.makeDecoder().decode(SkillSidecar.self, from: data)
    }

    func writeSidecar(_ sidecar: SkillSidecar, in folderURL: URL) throws {
        do {
            let data = try CanonicalJSON.makeEncoder().encode(sidecar)
            try data.write(to: folderURL.appendingPathComponent(".promptboard.json"), options: .atomic)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }

    func supportingFiles(in folderURL: URL) -> [SkillFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        let basePath = folderURL.standardizedFileURL.path
        var files: [SkillFile] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(basePath + "/") else { continue }
            let relative = String(path.dropFirst(basePath.count + 1))
            if relative == "SKILL.md" || relative == ".promptboard.json" { continue }
            files.append(SkillFile(relativePath: relative))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    func folderCreationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    // Reads one supporting file of a skill by id, refusing paths that escape the folder.
    public func skillFileData(id: UUID, relativePath: String) throws -> Data {
        guard let found = try findSkillFolder(id: id) else {
            throw LibraryRepositoryError.skillNotFound(id)
        }
        let fileURL = found.url.appendingPathComponent(relativePath)
        let base = found.url.standardizedFileURL.path
        guard fileURL.standardizedFileURL.path.hasPrefix(base + "/") else {
            throw LibraryRepositoryError.invalidSkillSource(path: relativePath)
        }
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }

    // Deterministic id for a skill folder that has no sidecar (e.g. hand-dropped),
    // so it keeps a stable identity across reloads. FNV-1a, dependency-free.
    static func stableSkillID(forName name: String) -> UUID {
        let seed = Array("promptboard/skill/\(name)".utf8)
        var low: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed { low = (low ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        var high: UInt64 = 0x0000_0100_0000_01b3
        for byte in seed.reversed() { high = (high ^ UInt64(byte)) &* 0xcbf2_9ce4_8422_2325 }
        func octets(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> (UInt64($0) * 8)) & 0xff) } }
        let bytes = octets(high) + octets(low)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func logWarning(_ message: String) {
        FileHandle.standardError.write(Data("PromptBoard: \(message)\n".utf8))
    }
}
