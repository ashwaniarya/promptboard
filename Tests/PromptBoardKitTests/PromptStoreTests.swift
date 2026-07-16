import Foundation
import Testing
@testable import PromptBoardKit

@MainActor
struct PromptStoreTests {
    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func firstRunSeedsSamplePrompts() {
        let directory = makeTemporaryDirectory()
        let store = PromptStore(directoryURL: directory)

        #expect(store.prompts.count == SeedPrompts.samples.count)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("prompts.json").path))
    }

    @Test func addedPromptRoundTripsAcrossStoreInstances() {
        let directory = makeTemporaryDirectory()
        let firstStore = PromptStore(directoryURL: directory)
        let added = firstStore.add(title: "Test Title", content: "Test content with unicode: café ✓")

        let secondStore = PromptStore(directoryURL: directory)
        let reloaded = secondStore.prompts.first { $0.id == added.id }

        #expect(reloaded != nil)
        #expect(reloaded?.title == "Test Title")
        #expect(reloaded?.content == "Test content with unicode: café ✓")
    }

    @Test func updatePersistsNewContentAndBumpsUpdatedAt() throws {
        let directory = makeTemporaryDirectory()
        let store = PromptStore(directoryURL: directory)
        let original = store.add(title: "Before", content: "old")

        store.update(id: original.id, title: "After", content: "new")

        let inMemory = try #require(store.prompts.first { $0.id == original.id })
        #expect(inMemory.updatedAt >= original.updatedAt)

        let reloaded = try #require(PromptStore(directoryURL: directory).prompts.first { $0.id == original.id })
        #expect(reloaded.title == "After")
        #expect(reloaded.content == "new")
        #expect(reloaded.updatedAt >= reloaded.createdAt)
    }

    @Test func datesRoundTripWithSubSecondPrecision() throws {
        let directory = makeTemporaryDirectory()
        let store = PromptStore(directoryURL: directory)
        let added = store.add(title: "Precise", content: "x")

        let reloaded = try #require(PromptStore(directoryURL: directory).prompts.first { $0.id == added.id })

        #expect(abs(reloaded.updatedAt.timeIntervalSince(added.updatedAt)) < 0.005)
    }

    @Test func deleteRemovesPromptPersistently() {
        let directory = makeTemporaryDirectory()
        let store = PromptStore(directoryURL: directory)
        let added = store.add(title: "Doomed", content: "gone soon")

        store.delete(id: added.id)

        let reloaded = PromptStore(directoryURL: directory)
        #expect(!reloaded.prompts.contains { $0.id == added.id })
    }

    @Test func emptyTitleDefaultsToUntitled() {
        let directory = makeTemporaryDirectory()
        let store = PromptStore(directoryURL: directory)

        let added = store.add(title: "   \n", content: "body")

        #expect(added.title == "Untitled")
    }

    @Test func corruptFileIsQuarantinedAndReseeded() throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("prompts.json")
        try Data("not json at all {{{".utf8).write(to: fileURL)

        let store = PromptStore(directoryURL: directory)

        #expect(store.prompts.count == SeedPrompts.samples.count)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents.contains { $0.hasPrefix("prompts.json.corrupt-") })
    }
}
