import Foundation
import Observation

@MainActor
@Observable
public final class PromptStore {
    public private(set) var prompts: [Prompt] = []

    private let repository: PromptRepository
    private(set) var lastKnownFileData: Data?
    @ObservationIgnored private var watcher: DirectoryChangeWatcher?
    @ObservationIgnored private var pendingReloadTask: Task<Void, Never>?

    public static var defaultDirectoryURL: URL {
        PromptRepository.defaultDirectoryURL
    }

    public init(directoryURL: URL) {
        repository = PromptRepository(directoryURL: directoryURL)
        loadInitial()
    }

    @discardableResult
    public func add(title: String, content: String) -> Prompt {
        do {
            let mutation = try repository.add(title: title, content: content)
            apply(mutation)
            return mutation.prompt
        } catch {
            reportFailure(error)
            let prompt = Prompt(title: PromptRepository.normalizedTitle(title), content: content)
            prompts.append(prompt)
            return prompt
        }
    }

    public func update(id: UUID, title: String, content: String) {
        do {
            apply(try repository.update(id: id, title: title, content: content))
        } catch PromptRepositoryError.promptNotFound {
        } catch {
            reportFailure(error)
            guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
            prompts[index].title = PromptRepository.normalizedTitle(title)
            prompts[index].content = content
            prompts[index].updatedAt = Date()
        }
    }

    public func delete(id: UUID) {
        do {
            apply(try repository.delete(id: id))
        } catch PromptRepositoryError.promptNotFound {
            prompts.removeAll { $0.id == id }
        } catch {
            reportFailure(error)
            prompts.removeAll { $0.id == id }
        }
    }

    public func startWatchingForExternalChanges() {
        guard watcher == nil else { return }
        try? repository.ensureDirectoryExists()
        watcher = DirectoryChangeWatcher(directoryURL: repository.directoryURL) { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleReload()
            }
        }
    }

    public func reloadFromDiskIfChanged() {
        guard let loaded = try? repository.loadIfPresent(),
              loaded.fileData != lastKnownFileData else { return }
        applyLoad(loaded)
    }

    private func scheduleReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reloadFromDiskIfChanged()
        }
    }

    private func loadInitial() {
        do {
            if let loaded = try repository.loadIfPresent() {
                applyLoad(loaded)
            } else {
                applyLoad(try repository.seedIfMissing(with: SeedPrompts.samples))
            }
        } catch PromptRepositoryError.corruptData {
            recoverFromCorruptFile()
        } catch {
            reportFailure(error)
            prompts = SeedPrompts.samples
        }
    }

    private func recoverFromCorruptFile() {
        do {
            let recovered = try repository.withExclusiveLock {
                if let loaded = try? repository.loadIfPresent() {
                    return loaded
                }
                repository.quarantineDataFile()
                let fileData = try repository.save(SeedPrompts.samples)
                return PromptRepository.LoadResult(prompts: SeedPrompts.samples, fileData: fileData)
            }
            applyLoad(recovered)
        } catch {
            reportFailure(error)
            prompts = SeedPrompts.samples
        }
    }

    private func apply(_ mutation: PromptRepository.Mutation) {
        prompts = mutation.prompts
        lastKnownFileData = mutation.fileData
    }

    private func applyLoad(_ loaded: PromptRepository.LoadResult) {
        prompts = loaded.prompts
        lastKnownFileData = loaded.fileData
    }

    private func reportFailure(_ error: any Error) {
        FileHandle.standardError.write(Data("PromptStore repository failure: \(error)\n".utf8))
    }
}
