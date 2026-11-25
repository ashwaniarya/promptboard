import Foundation
import Testing
@testable import PromptBoardKit

struct ChainProgressTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardChainProgressTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeProgress() throws -> ChainProgress {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ChainProgress(fileURL: directory.appendingPathComponent("chain-state.json"))
    }

    @Test func missingFileReadsZero() throws {
        #expect(try makeProgress().index(for: UUID(), stepCount: 3) == 0)
    }

    @Test func setThenReadRoundTrips() throws {
        let progress = try makeProgress()
        let chainID = UUID()

        try progress.setIndex(2, for: chainID)

        #expect(progress.index(for: chainID, stepCount: 5) == 2)
    }

    @Test func indexClampsWhenChainShrinks() throws {
        let progress = try makeProgress()
        let chainID = UUID()

        try progress.setIndex(5, for: chainID)

        #expect(progress.index(for: chainID, stepCount: 2) == 2)
    }

    @Test func corruptFileReadsZeroAndSetRecovers() throws {
        let progress = try makeProgress()
        let chainID = UUID()
        try Data("{oops".utf8).write(to: progress.fileURL)

        #expect(progress.index(for: chainID, stepCount: 3) == 0)
        try progress.setIndex(1, for: chainID)
        #expect(progress.index(for: chainID, stepCount: 3) == 1)
    }

    @Test func pruneDropsUnknownIDs() throws {
        let progress = try makeProgress()
        let kept = UUID()
        let dropped = UUID()
        try progress.setIndex(1, for: kept)
        try progress.setIndex(2, for: dropped)

        try progress.prune(keeping: [kept])

        #expect(progress.index(for: dropped, stepCount: 3) == 0)
        #expect(progress.index(for: kept, stepCount: 3) == 1)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: progress.fileURL)) as? [String: Int]
        #expect(object?.count == 1)
    }

    @Test func pruneWithoutFileCreatesNothing() throws {
        let progress = try makeProgress()

        try progress.prune(keeping: [])

        #expect(!FileManager.default.fileExists(atPath: progress.fileURL.path))
    }

    @Test func resetWritesZeroAndKeepsOtherChains() throws {
        let progress = try makeProgress()
        let first = UUID()
        let second = UUID()
        try progress.setIndex(2, for: first)
        try progress.setIndex(1, for: second)

        try progress.reset(for: first)

        #expect(progress.index(for: first, stepCount: 3) == 0)
        #expect(progress.index(for: second, stepCount: 3) == 1)
    }

    @Test @MainActor func resetNeverWritesLibraryFiles() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let libraryURL = LibraryRepository(directoryURL: directory, syncTargets: .temporary()).libraryURL
        let chain = try #require(store.addChain(title: "Ship", steps: [.custom(text: "a"), .custom(text: "b")]))
        let libraryFileDates = {
            let files = FileManager.default.enumerator(at: libraryURL, includingPropertiesForKeys: [.contentModificationDateKey])?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "md" } ?? []
            return Dictionary(uniqueKeysWithValues: files.map {
                ($0.path, try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            })
        }
        let before = libraryFileDates()

        try store.chainProgress.setIndex(1, for: chain.id)
        try store.chainProgress.setIndex(2, for: chain.id)
        try store.chainProgress.reset(for: chain.id)

        #expect(!before.isEmpty)
        #expect(libraryFileDates() == before)

        try store.chainProgress.setIndex(2, for: chain.id)
        let restarted = try store.restartChain(chain)

        #expect(restarted.selectedIndex == 0)
        #expect(store.chainProgress.index(for: chain.id, stepCount: 2) == 0)
        #expect(libraryFileDates() == before)
    }

    @Test func stateFileIsOutsideLibraryDirectory() {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())

        #expect(!repository.chainStateURL.path.hasPrefix(repository.libraryURL.path))
    }

    @Test @MainActor func storePrunesDeletedChainOnLaunch() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        try repository.ensureLibraryDirectories()
        let ghost = UUID()
        try ChainProgress(fileURL: repository.chainStateURL).setIndex(1, for: ghost)

        _ = LibraryStore(directoryURL: directory, syncTargets: .temporary())

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: repository.chainStateURL)) as? [String: Int]
        #expect(object?[ghost.uuidString] == nil)
    }
}
