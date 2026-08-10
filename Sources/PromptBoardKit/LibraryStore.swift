import Foundation
import Observation

// Observable cache over LibraryRepository. Keeps the app's non-throwing surface,
// live-reloads external changes (rescan + content signature to suppress our own
// writes), and migrates/seeds on first run. Skill-authoring stays in the repository.
@MainActor
@Observable
public final class LibraryStore {
    public private(set) var items: [LibraryEntry] = []
    public private(set) var syncConflicts: [LibraryRepository.SyncConflict] = []
    public private(set) var externalItems: [ExternalItem] = []

    private let repository: LibraryRepository
    private var lastSignature = ""
    @ObservationIgnored private var watchers: [DirectoryChangeWatcher] = []
    @ObservationIgnored private var pendingReloadTask: Task<Void, Never>?

    public static var defaultDirectoryURL: URL {
        LibraryRepository.defaultDirectoryURL
    }

    public var prompts: [Prompt] {
        items.compactMap { if case .prompt(let prompt) = $0 { prompt } else { nil } }
    }

    public var groups: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for case let group? in items.map(\.group) where !seen.contains(group) {
            seen.insert(group)
            ordered.append(group)
        }
        return ordered.sorted()
    }

    public init(directoryURL: URL, syncTargets: SyncTargets) {
        repository = LibraryRepository(directoryURL: directoryURL, syncTargets: syncTargets)
        loadInitial()
    }

    // MARK: - Prompt mutations

    @discardableResult
    public func add(title: String, content: String, group: String? = nil) -> Prompt {
        do {
            let prompt = try repository.addPrompt(title: title, content: content, group: group)
            refreshFromDisk()
            return prompt
        } catch {
            reportFailure(error)
            let prompt = Prompt(title: LibraryRepository.normalizedTitle(title), content: content, group: group)
            items.append(.prompt(prompt))
            return prompt
        }
    }

    public func update(id: UUID, title: String, content: String) {
        do {
            _ = try repository.updatePrompt(id: id, title: title, content: content)
            refreshFromDisk()
        } catch LibraryRepositoryError.promptNotFound {
        } catch {
            reportFailure(error)
        }
    }

    // Routes by id: a prompt if one matches, otherwise a skill.
    public func delete(id: UUID) {
        do {
            _ = try repository.deletePrompt(id: id)
            refreshFromDisk()
            return
        } catch LibraryRepositoryError.promptNotFound {
        } catch {
            reportFailure(error)
            return
        }
        do {
            _ = try repository.deleteSkill(id: id)
            refreshFromDisk()
        } catch LibraryRepositoryError.skillNotFound {
        } catch {
            reportFailure(error)
        }
    }

    public func skillFileText(id: UUID, relativePath: String) -> String? {
        guard let data = try? repository.skillFileData(id: id, relativePath: relativePath) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Skill authoring

    @discardableResult
    public func createSkill(name: String, description: String, group: String?, body: String) -> Skill? {
        do {
            let skill = try repository.createSkill(name: name, description: description, group: group, body: body)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func updateSkill(id: UUID, name: String, description: String, group: String?, body: String) -> Skill? {
        do {
            let skill = try repository.updateSkill(id: id, name: name, description: description, group: group, body: body)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func writeSkillFile(id: UUID, relativePath: String, data: Data) -> Skill? {
        do {
            let skill = try repository.writeSkillFile(id: id, relativePath: relativePath, data: data)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func renameSkillFile(id: UUID, from source: String, to destination: String) -> Skill? {
        do {
            let skill = try repository.renameSkillFile(id: id, from: source, to: destination)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func deleteSkillFile(id: UUID, relativePath: String) -> Skill? {
        do {
            let skill = try repository.deleteSkillFile(id: id, relativePath: relativePath)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func promotePromptToSkill(
        promptID: UUID, name: String, description: String, group: String?, removingPrompt: Bool
    ) -> Skill? {
        do {
            let skill = try repository.promotePromptToSkill(
                promptID: promptID, name: name, description: description, group: group, removingPrompt: removingPrompt
            )
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    // MARK: - External adoption

    public func refreshExternalItems(roots: [ExternalLibraryScanner.Root] = ExternalLibraryScanner.defaultRoots()) {
        externalItems = ExternalLibraryScanner.scan(roots: roots, storageRoot: repository.directoryURL)
    }

    @discardableResult
    public func adoptExternal(_ item: ExternalItem, mode: LibraryRepository.AdoptMode) -> Bool {
        do {
            try repository.adoptExternal(item, mode: mode)
            refreshFromDisk()
            refreshExternalItems()
            return true
        } catch {
            reportFailure(error)
            return false
        }
    }

    // MARK: - Live reload

    public func startWatchingForExternalChanges() {
        guard watchers.isEmpty else { return }
        try? repository.ensureLibraryDirectories()
        for directory in [repository.promptsDirectoryURL, repository.skillsDirectoryURL] {
            if let watcher = DirectoryChangeWatcher(directoryURL: directory, onChange: { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }) {
                watchers.append(watcher)
            }
        }
    }

    public func reloadFromDiskIfChanged() {
        guard let load = try? repository.load() else { return }
        let signature = Self.signature(of: load.items)
        guard signature != lastSignature else { return }
        items = load.items
        lastSignature = signature
        // A prompt added by the CLI or MCP while the app runs reaches us only here;
        // without this, it would not sync until the next in-app action.
        reconcileSync()
    }

    private func scheduleReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reloadFromDiskIfChanged()
        }
    }

    // MARK: - Internals

    private func loadInitial() {
        let freshInstall = !FileManager.default.fileExists(atPath: repository.libraryURL.path)
        let migrated = (try? repository.migrateLegacyIfNeeded()) ?? false
        if freshInstall, !migrated {
            _ = try? repository.seedPromptsIfEmpty(SeedPrompts.samples)
        }
        _ = try? repository.migrateGroupsToFoldersIfNeeded()
        refreshFromDisk()
        refreshExternalItems()
    }

    // Reads the on-disk state back after our own writes so the resulting signature
    // matches what a subsequent watcher-triggered reload will compute (self-write suppression).
    private func refreshFromDisk() {
        let load = (try? repository.load()) ?? LibraryRepository.Load(items: [], skippedPaths: [])
        items = load.items
        lastSignature = Self.signature(of: load.items)
        reconcileSync()
    }

    // Writes only to Export/ and the external target dirs (both outside Library/),
    // so it never retriggers the prompts/skills watchers that drive reloadFromDiskIfChanged.
    private func reconcileSync() {
        do {
            syncConflicts = try repository.reconcileSync()
        } catch {
            reportFailure(error)
        }
    }

    private static func signature(of items: [LibraryEntry]) -> String {
        items.map { item -> String in
            switch item {
            case .prompt(let prompt):
                "p:\(prompt.id.uuidString):\(prompt.updatedAt.timeIntervalSince1970):\(prompt.content.count)"
            case .skill(let skill):
                "s:\(skill.id.uuidString):\(skill.updatedAt.timeIntervalSince1970):\(skill.body.count)"
            }
        }
        .sorted()
        .joined(separator: ";")
    }

    private func reportFailure(_ error: any Error) {
        FileHandle.standardError.write(Data("LibraryStore repository failure: \(error)\n".utf8))
    }
}
