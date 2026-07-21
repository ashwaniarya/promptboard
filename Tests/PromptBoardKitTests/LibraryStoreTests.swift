import Foundation
import Testing
@testable import PromptBoardKit

@MainActor
struct LibraryStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func promptTitles(_ store: LibraryStore) -> [String] {
        store.items.compactMap { if case .prompt(let prompt) = $0 { prompt.title } else { nil } }
    }

    @Test func firstRunSeedsSamplePromptsIntoTheFolderLibrary() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)

        #expect(store.items.count == SeedPrompts.samples.count)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library/prompts").path))
    }

    @Test func addedPromptRoundTripsAcrossStoreInstances() {
        let directory = temporaryDirectory()
        let first = LibraryStore(directoryURL: directory)
        let added = first.add(title: "Test Title", content: "unicode: café ✓")

        let second = LibraryStore(directoryURL: directory)
        let reloaded = second.items.first { $0.id == added.id }

        #expect(reloaded != nil)
        #expect(reloaded?.title == "Test Title")
    }

    @Test func updatePersistsAcrossInstancesAndBumpsUpdatedAt() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let original = store.add(title: "Before", content: "old")

        store.update(id: original.id, title: "After", content: "new")

        let reloaded = try #require(LibraryStore(directoryURL: directory).items.first { $0.id == original.id })
        #expect(reloaded.title == "After")
        #expect(reloaded.updatedAt >= original.updatedAt)
    }

    @Test func datesRoundTripWithSubSecondPrecision() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let added = store.add(title: "Precise", content: "x")

        let reloaded = try #require(LibraryStore(directoryURL: directory).items.first { $0.id == added.id })
        #expect(abs(reloaded.updatedAt.timeIntervalSince(added.updatedAt)) < 0.005)
    }

    @Test func deleteRemovesPromptPersistently() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let added = store.add(title: "Doomed", content: "gone soon")

        store.delete(id: added.id)

        #expect(!LibraryStore(directoryURL: directory).items.contains { $0.id == added.id })
    }

    @Test func emptyTitleDefaultsToUntitled() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let added = store.add(title: "   \n", content: "body")
        #expect(added.title == "Untitled")
    }

    @Test func migratesLegacyPromptsJsonOnFirstLoad() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = [Prompt(title: "Legacy One", content: "a"), Prompt(title: "Legacy Two", content: "b")]
        try CanonicalJSON.makeEncoder().encode(legacy)
            .write(to: directory.appendingPathComponent("prompts.json"))

        let store = LibraryStore(directoryURL: directory)

        #expect(Set(promptTitles(store)) == ["Legacy One", "Legacy Two"])
        // legacy content is migrated, not re-seeded with samples
        #expect(!promptTitles(store).contains { SeedPrompts.samples.map(\.title).contains($0) && !["Legacy One", "Legacy Two"].contains($0) })
    }

    @Test func reloadAppliesExternalPromptWrite() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let external = try LibraryRepository(directoryURL: directory).addPrompt(title: "External", content: "from agent")

        store.reloadFromDiskIfChanged()

        #expect(store.items.contains { $0.id == external.id })
    }

    @Test func ownWriteDoesNotTriggerAReloadChange() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let added = store.add(title: "Mine", content: "self write")
        let countAfterAdd = store.items.count

        store.reloadFromDiskIfChanged()

        #expect(store.items.count == countAfterAdd)
        #expect(store.items.filter { $0.id == added.id }.count == 1)
    }

    @Test func externalSkillFolderAppearsOnReload() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let skillFolder = directory.appendingPathComponent("Library/skills/dropped")
        try FileManager.default.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        try Data("---\nname: dropped\ndescription: A dropped skill\n---\n# Body".utf8)
            .write(to: skillFolder.appendingPathComponent("SKILL.md"))

        store.reloadFromDiskIfChanged()

        #expect(store.items.contains { $0.kind == .skill && $0.title == "dropped" })
    }

    @Test func watcherAppliesExternalChangeAutomatically() async throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        store.startWatchingForExternalChanges()

        let external = try LibraryRepository(directoryURL: directory).addPrompt(title: "Watched", content: "x")

        for _ in 0..<40 where !store.items.contains(where: { $0.id == external.id }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.items.contains { $0.id == external.id })
    }

    @Test func malformedItemDoesNotBreakTheStore() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let good = store.add(title: "Good", content: "ok")
        try Data("---\ntitle: no id\n---\nbody".utf8)
            .write(to: directory.appendingPathComponent("Library/prompts/broken.md"))

        store.reloadFromDiskIfChanged()

        #expect(store.items.contains { $0.id == good.id })
    }
}
