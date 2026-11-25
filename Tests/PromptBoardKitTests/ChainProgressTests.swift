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
