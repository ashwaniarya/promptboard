import Foundation

public enum PromptRepositoryError: Error, Sendable {
    case corruptData(path: String, underlying: any Error)
    case promptNotFound(UUID)
    case nothingToUpdate
    case lockTimeout(path: String)
    case ioFailure(underlying: any Error)
}

public struct PromptRepository: Sendable {
    public let directoryURL: URL
    public let dataFileURL: URL
    private let lockFileURL: URL

    public static var defaultDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptBoard", isDirectory: true)
    }

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.dataFileURL = directoryURL.appendingPathComponent("prompts.json")
        self.lockFileURL = directoryURL.appendingPathComponent(".prompts.json.lock")
    }

    public struct LoadResult: Sendable {
        public let prompts: [Prompt]
        public let fileData: Data
    }

    public struct Mutation: Sendable {
        public let prompt: Prompt
        public let prompts: [Prompt]
        public let fileData: Data
    }

    public func loadIfPresent() throws -> LoadResult? {
        let data: Data
        do {
            data = try Data(contentsOf: dataFileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw PromptRepositoryError.ioFailure(underlying: error)
        }
        do {
            let prompts = try Self.makeDecoder().decode([Prompt].self, from: data)
            return LoadResult(prompts: prompts, fileData: data)
        } catch {
            throw PromptRepositoryError.corruptData(path: dataFileURL.path, underlying: error)
        }
    }

    @discardableResult
    public func save(_ prompts: [Prompt]) throws -> Data {
        do {
            try ensureDirectoryExists()
            let data = try Self.makeEncoder().encode(prompts)
            try data.write(to: dataFileURL, options: .atomic)
            return data
        } catch {
            throw PromptRepositoryError.ioFailure(underlying: error)
        }
    }

    @discardableResult
    public func quarantineDataFile() -> URL? {
        let epoch = Int(Date().timeIntervalSince1970)
        let backupURL = directoryURL.appendingPathComponent("prompts.json.corrupt-\(epoch)")
        do {
            try FileManager.default.moveItem(at: dataFileURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    public func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // Locks a sidecar file because .atomic saves replace prompts.json's inode on
    // every write, which would silently detach any lock held on the data file itself.
    // Non-reentrant: never call the self-locking conveniences from inside `body`.
    public func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        do {
            try ensureDirectoryExists()
        } catch {
            throw PromptRepositoryError.ioFailure(underlying: error)
        }
        let lockDescriptor = open(lockFileURL.path, O_CREAT | O_WRONLY | O_CLOEXEC, 0o644)
        guard lockDescriptor >= 0 else {
            throw PromptRepositoryError.ioFailure(
                underlying: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            )
        }
        defer { close(lockDescriptor) }

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while flock(lockDescriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else {
                throw PromptRepositoryError.lockTimeout(path: lockFileURL.path)
            }
            usleep(20_000)
        }
        return try body()
    }

    @discardableResult
    public func add(title: String, content: String) throws -> Mutation {
        try withExclusiveLock {
            var prompts = try loadIfPresent()?.prompts ?? []
            let prompt = Prompt(title: Self.normalizedTitle(title), content: content)
            prompts.append(prompt)
            let fileData = try save(prompts)
            return Mutation(prompt: prompt, prompts: prompts, fileData: fileData)
        }
    }

    @discardableResult
    public func update(id: UUID, title: String?, content: String?) throws -> Mutation {
        guard title != nil || content != nil else {
            throw PromptRepositoryError.nothingToUpdate
        }
        return try withExclusiveLock {
            var prompts = try loadIfPresent()?.prompts ?? []
            guard let index = prompts.firstIndex(where: { $0.id == id }) else {
                throw PromptRepositoryError.promptNotFound(id)
            }
            if let title {
                prompts[index].title = Self.normalizedTitle(title)
            }
            if let content {
                prompts[index].content = content
            }
            prompts[index].updatedAt = Date()
            let fileData = try save(prompts)
            return Mutation(prompt: prompts[index], prompts: prompts, fileData: fileData)
        }
    }

    @discardableResult
    public func delete(id: UUID) throws -> Mutation {
        try withExclusiveLock {
            var prompts = try loadIfPresent()?.prompts ?? []
            guard let index = prompts.firstIndex(where: { $0.id == id }) else {
                throw PromptRepositoryError.promptNotFound(id)
            }
            let removed = prompts.remove(at: index)
            let fileData = try save(prompts)
            return Mutation(prompt: removed, prompts: prompts, fileData: fileData)
        }
    }

    @discardableResult
    public func seedIfMissing(with samples: [Prompt]) throws -> LoadResult {
        try withExclusiveLock {
            if let existing = try loadIfPresent() {
                return existing
            }
            let fileData = try save(samples)
            return LoadResult(prompts: samples, fileData: fileData)
        }
    }

    public static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    public static func makeEncoder() -> JSONEncoder { CanonicalJSON.makeEncoder() }
    public static func makeDecoder() -> JSONDecoder { CanonicalJSON.makeDecoder() }
}
