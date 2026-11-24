import Foundation

// Run state for chains: {"<chain uuid>": nextStepIndex}. Lives outside Library/
// so stepping through a chain never touches a library file or fires the watcher.
// shortcut: no flock, only the app writes this file; add the library lock if the CLI ever steps chains
public struct ChainProgress: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func index(for chainID: UUID, stepCount: Int) -> Int {
        min(max(readState()[chainID.uuidString] ?? 0, 0), max(stepCount, 0))
    }

    public func setIndex(_ index: Int, for chainID: UUID) throws {
        var state = readState()
        state[chainID.uuidString] = index
        try writeState(state)
    }

    public func prune(keeping chainIDs: Set<UUID>) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let state = readState()
        let keptKeys = Set(chainIDs.map(\.uuidString))
        let pruned = state.filter { keptKeys.contains($0.key) }
        guard pruned != state else { return }
        try writeState(pruned)
    }

    private func readState() -> [String: Int] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func writeState(_ state: [String: Int]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }
}
