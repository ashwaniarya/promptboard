import Foundation
import Testing
@testable import PromptBoardKit

struct ChainRepositoryTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardChainTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func promptsDir(_ base: URL) -> URL {
        base.appendingPathComponent("Library/prompts", isDirectory: true)
    }

    @discardableResult
    private func writeRawChain(in base: URL, folder: String = "Work", id: UUID = UUID(), promptID: UUID = UUID()) throws -> (url: URL, id: UUID) {
        let directory = promptsDir(base).appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = """
        ---
        id: \(id.uuidString)
        kind: chain
        title: Ship
        createdAt: 2026-11-24T10:00:00Z
        updatedAt: 2026-11-24T10:00:00Z
        ---

        - @\(promptID.uuidString)

        ```
        review it
        ```

        """
        let url = directory.appendingPathComponent("ship.md")
        try Data(text.utf8).write(to: url)
        return (url, id)
    }

    private func chains(_ items: [LibraryEntry]) -> [Chain] {
        items.compactMap { if case .chain(let chain) = $0 { chain } else { nil } }
    }

    @Test func loadRoutesChainFileToChainEntry() throws {
        let directory = temporaryDirectory()
        let (_, chainID) = try writeRawChain(in: directory)
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        let items = try repository.load().items

        let loaded = chains(items)
        #expect(loaded.count == 1)
        #expect(loaded.first?.steps.count == 2)
        #expect(loaded.first?.group == "Work")
        #expect(!items.contains { if case .prompt(let prompt) = $0 { prompt.id == chainID } else { false } })
    }

    @Test @MainActor func storePromptsExcludeChains() throws {
        let directory = temporaryDirectory()
        let (_, chainID) = try writeRawChain(in: directory)

        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())

        #expect(!store.prompts.contains { $0.id == chainID })
        #expect(store.items.first { $0.id == chainID }?.kind == .chain)
    }

    @Test func promptMutationsIgnoreChainFiles() throws {
        let directory = temporaryDirectory()
        let (url, chainID) = try writeRawChain(in: directory)
        let before = try Data(contentsOf: url)
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        do {
            try repository.updatePrompt(id: chainID, title: "x", content: nil)
            Issue.record("expected promptNotFound")
        } catch LibraryRepositoryError.promptNotFound(let id) {
            #expect(id == chainID)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func reconcileSyncDoesNotExportChains() throws {
        let directory = temporaryDirectory()
        try writeRawChain(in: directory)
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        try repository.reconcileSync()

        let exported = repository.exportSkillsURL.appendingPathComponent("ship")
        #expect(!FileManager.default.fileExists(atPath: exported.path))
    }

    @Test func chainEntryCodableRoundTrip() throws {
        let entry = LibraryEntry.chain(Chain(
            title: "Ship", steps: [.linked(promptID: UUID()), .custom(text: "go")],
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000)
        ))

        let data = try CanonicalJSON.makeEncoder().encode(entry)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["kind"] as? String == "chain")
        #expect(try CanonicalJSON.makeDecoder().decode(LibraryEntry.self, from: data) == entry)
    }

    @Test func chainKindFoldersUsePromptsTree() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())

        #expect(try repository.folderURL(for: .chain, path: "A")
            == repository.promptsDirectoryURL.appendingPathComponent("A", isDirectory: true))
    }

    @Test func writeChainThenLoadRoundTrips() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        try repository.ensureLibraryDirectories()
        let chain = Chain(
            title: "Ship", steps: [.custom(text: "one"), .linked(promptID: UUID())],
            createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        try repository.writeChain(chain, to: repository.promptsDirectoryURL.appendingPathComponent("ship.md"))

        #expect(chains(try repository.load().items) == [chain])
    }

    private func expectChainNotFound(_ id: UUID, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("expected chainNotFound")
        } catch LibraryRepositoryError.chainNotFound(let missing) {
            #expect(missing == id)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func addChainWritesKindChainFile() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        let steps: [Chain.Step] = [.linked(promptID: UUID()), .custom(text: "review")]

        let chain = try repository.addChain(title: "Ship", steps: steps)

        let text = try String(contentsOf: repository.promptsDirectoryURL.appendingPathComponent("ship.md"), encoding: .utf8)
        #expect(text.contains("kind: chain"))
        #expect(text.contains("- @"))
        #expect(chains(try repository.load().items).first { $0.id == chain.id }?.steps == steps)
    }

    @Test func addChainSlugAvoidsPromptCollision() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        _ = try repository.addPrompt(title: "Review", content: "x")

        _ = try repository.addChain(title: "Review", steps: [])

        let url = repository.promptsDirectoryURL.appendingPathComponent("review-2.md")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("kind: chain"))
    }

    @Test func updateChainRewritesStepsAndBumpsUpdatedAt() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let original = try repository.addChain(title: "Ship", steps: [.custom(text: "a")])
        let newSteps: [Chain.Step] = [.custom(text: "b"), .linked(promptID: UUID())]

        _ = try repository.updateChain(id: original.id, title: "Ship it", steps: newSteps)

        let loaded = try #require(chains(try repository.load().items).first)
        #expect(loaded.steps == newSteps)
        #expect(loaded.title == "Ship it")
        #expect(loaded.updatedAt > original.updatedAt)
        #expect(CanonicalJSON.isoString(from: loaded.createdAt) == CanonicalJSON.isoString(from: original.createdAt))
    }

    @Test func deleteChainKeepsLinkedPrompt() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let prompt = try repository.addPrompt(title: "Spec", content: "write it")
        let chain = try repository.addChain(title: "Ship", steps: [.linked(promptID: prompt.id)])

        _ = try repository.deleteChain(id: chain.id)

        let promptsDir = repository.promptsDirectoryURL
        #expect(!FileManager.default.fileExists(atPath: promptsDir.appendingPathComponent("ship.md").path))
        #expect(FileManager.default.fileExists(atPath: promptsDir.appendingPathComponent("spec.md").path))
    }

    @Test func deleteMovingToTrashLeavesFileInTrash() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let marker = "trash-test-\(UUID().uuidString.lowercased())"
        let prompt = try repository.addPrompt(title: marker + "-prompt", content: "x")
        let chain = try repository.addChain(title: marker + "-chain", steps: [.linked(promptID: prompt.id)])

        _ = try repository.deletePrompt(id: prompt.id, movingToTrash: true)
        _ = try repository.deleteChain(id: chain.id, movingToTrash: true)

        #expect(try repository.load().items.isEmpty)
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        for name in [marker + "-chain.md", marker + "-prompt.md"] {
            let trashed = trash.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: trashed.path))
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    @Test @MainActor func chainCountLinkingCountsEachChainOnce() throws {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let spec = store.add(title: "Spec", content: "write it")
        let unused = store.add(title: "Unused", content: "x")
        _ = store.addChain(title: "Ship", steps: [.linked(promptID: spec.id), .linked(promptID: spec.id)])
        _ = store.addChain(title: "Review", steps: [.custom(text: "a"), .linked(promptID: spec.id)])
        _ = store.addChain(title: "Other", steps: [.custom(text: "b")])

        #expect(store.chainCount(linking: spec.id) == 2)
        #expect(store.chainCount(linking: unused.id) == 0)
    }

    @Test func moveChainRelocatesIntoFolder() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let chain = try repository.addChain(title: "Ship", steps: [])

        try repository.moveChain(id: chain.id, toFolder: "Work")

        #expect(chains(try repository.load().items).first?.group == "Work")
    }

    @Test func unknownChainIDThrowsChainNotFound() throws {
        let repository = LibraryRepository(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let ghost = UUID()

        expectChainNotFound(ghost) { _ = try repository.updateChain(id: ghost, title: "x", steps: []) }
        expectChainNotFound(ghost) { _ = try repository.deleteChain(id: ghost) }
        expectChainNotFound(ghost) { try repository.moveChain(id: ghost, toFolder: "Work") }
    }

    @Test @MainActor func storeDeleteRoutesToChain() throws {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let chain = try #require(store.addChain(title: "Ship", steps: [.custom(text: "a")]))
        #expect(store.chains.contains { $0.id == chain.id })

        store.delete(id: chain.id)

        #expect(!store.chains.contains { $0.id == chain.id })
    }

    @Test @MainActor func storeMoveItemRoutesToChain() throws {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let chain = try #require(store.addChain(title: "Ship", steps: []))

        #expect(store.moveItem(id: chain.id, toFolder: "Work"))
        #expect(store.chains.first { $0.id == chain.id }?.group == "Work")
    }
}
