import Foundation
import Testing
@testable import PromptBoardKit

@MainActor
struct LibraryStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func targets(claude: URL) -> SyncTargets {
        SyncTargets(claudeSkillsURL: claude, agentsSkillsURL: temporaryDirectory())
    }

    private func promptTitles(_ store: LibraryStore) -> [String] {
        store.items.compactMap { if case .prompt(let prompt) = $0 { prompt.title } else { nil } }
    }

    @Test func firstRunSeedsSamplePromptsIntoTheFolderLibrary() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())

        #expect(store.items.count == SeedPrompts.samples.count)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library/prompts").path))
    }

    @Test func addedPromptRoundTripsAcrossStoreInstances() {
        let directory = temporaryDirectory()
        let first = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let added = first.add(title: "Test Title", content: "unicode: café ✓")

        let second = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let reloaded = second.items.first { $0.id == added.id }

        #expect(reloaded != nil)
        #expect(reloaded?.title == "Test Title")
    }

    @Test func updatePersistsAcrossInstancesAndBumpsUpdatedAt() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let original = store.add(title: "Before", content: "old")

        store.update(id: original.id, title: "After", content: "new")

        let reloaded = try #require(LibraryStore(directoryURL: directory, syncTargets: .temporary()).items.first { $0.id == original.id })
        #expect(reloaded.title == "After")
        #expect(reloaded.updatedAt >= original.updatedAt)
    }

    @Test func datesRoundTripWithSubSecondPrecision() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let added = store.add(title: "Precise", content: "x")

        let reloaded = try #require(LibraryStore(directoryURL: directory, syncTargets: .temporary()).items.first { $0.id == added.id })
        #expect(abs(reloaded.updatedAt.timeIntervalSince(added.updatedAt)) < 0.005)
    }

    @Test func deleteRemovesPromptPersistently() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let added = store.add(title: "Doomed", content: "gone soon")

        store.delete(id: added.id)

        #expect(!LibraryStore(directoryURL: directory, syncTargets: .temporary()).items.contains { $0.id == added.id })
    }

    @Test func emptyTitleDefaultsToUntitled() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let added = store.add(title: "   \n", content: "body")
        #expect(added.title == "Untitled")
    }

    @Test func migratesLegacyPromptsJsonOnFirstLoad() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = [Prompt(title: "Legacy One", content: "a"), Prompt(title: "Legacy Two", content: "b")]
        try CanonicalJSON.makeEncoder().encode(legacy)
            .write(to: directory.appendingPathComponent("prompts.json"))

        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())

        #expect(Set(promptTitles(store)) == ["Legacy One", "Legacy Two"])
        // legacy content is migrated, not re-seeded with samples
        #expect(!promptTitles(store).contains { SeedPrompts.samples.map(\.title).contains($0) && !["Legacy One", "Legacy Two"].contains($0) })
    }

    @Test func reloadAppliesExternalPromptWrite() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let external = try LibraryRepository(directoryURL: directory, syncTargets: .temporary()).addPrompt(title: "External", content: "from agent")

        store.reloadFromDiskIfChanged()

        #expect(store.items.contains { $0.id == external.id })
    }

    @Test func ownWriteDoesNotTriggerAReloadChange() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let added = store.add(title: "Mine", content: "self write")
        let countAfterAdd = store.items.count

        store.reloadFromDiskIfChanged()

        #expect(store.items.count == countAfterAdd)
        #expect(store.items.filter { $0.id == added.id }.count == 1)
    }

    @Test func externalSkillFolderAppearsOnReload() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let skillFolder = directory.appendingPathComponent("Library/skills/dropped")
        try FileManager.default.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        try Data("---\nname: dropped\ndescription: A dropped skill\n---\n# Body".utf8)
            .write(to: skillFolder.appendingPathComponent("SKILL.md"))

        store.reloadFromDiskIfChanged()

        #expect(store.items.contains { $0.kind == .skill && $0.title == "dropped" })
    }

    @Test func watcherAppliesExternalChangeAutomatically() async throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        store.startWatchingForExternalChanges()

        let external = try LibraryRepository(directoryURL: directory, syncTargets: .temporary()).addPrompt(title: "Watched", content: "x")

        for _ in 0..<40 where !store.items.contains(where: { $0.id == external.id }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.items.contains { $0.id == external.id })
    }

    @Test func malformedItemDoesNotBreakTheStore() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let good = store.add(title: "Good", content: "ok")
        try Data("---\ntitle: no id\n---\nbody".utf8)
            .write(to: directory.appendingPathComponent("Library/prompts/broken.md"))

        store.reloadFromDiskIfChanged()

        #expect(store.items.contains { $0.id == good.id })
    }

    @Test func createSkillAppearsInItemsAndPersists() {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let store = LibraryStore(
            directoryURL: directory,
            syncTargets: targets(claude: claude)
        )

        let skill = store.createSkill(name: "Runbook", description: "deploy steps", group: "Ops", body: "# Go")

        #expect(skill != nil)
        #expect(store.items.contains { $0.kind == .skill && $0.title == "runbook" })
        #expect(LibraryStore(
            directoryURL: directory,
            syncTargets: targets(claude: claude)
        ).items.contains { $0.title == "runbook" })
    }

    @Test func updateSkillRenameReplacesTheCardKeepingID() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let skill = store.createSkill(name: "before", description: "d", group: nil, body: "")!

        let renamed = store.updateSkill(id: skill.id, name: "after", description: "d", group: nil, body: "")

        #expect(renamed?.id == skill.id)
        #expect(store.items.contains { $0.title == "after" })
        #expect(!store.items.contains { $0.title == "before" })
        #expect(store.items.filter { $0.id == skill.id }.count == 1)
    }

    @Test func skillFileWriteAndDeleteRoundTripThroughStore() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let skill = store.createSkill(name: "docs", description: "d", group: nil, body: "")!

        _ = store.writeSkillFile(id: skill.id, relativePath: "ref.md", data: Data("hi".utf8))
        #expect(store.skillFileText(id: skill.id, relativePath: "ref.md") == "hi")

        _ = store.deleteSkillFile(id: skill.id, relativePath: "ref.md")
        let reloaded = store.items.compactMap { if case .skill(let s) = $0 { s } else { nil } }.first { $0.id == skill.id }
        #expect(reloaded?.files.isEmpty == true)
    }

    @Test func promoteThroughStoreRemovesPromptAndAddsSkill() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let prompt = store.add(title: "Convert Me", content: "# body")

        let skill = store.promotePromptToSkill(
            promptID: prompt.id, name: "Convert Me", description: "d", group: nil, removingPrompt: true
        )

        #expect(skill != nil)
        #expect(!store.items.contains { $0.id == prompt.id })
        #expect(store.items.contains { $0.kind == .skill && $0.title == "convert-me" })
    }

    @Test func skillFileTextIsNilForNonUTF8Content() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let skill = store.createSkill(name: "bin", description: "d", group: nil, body: "")!

        _ = store.writeSkillFile(id: skill.id, relativePath: "notes.md", data: Data("hello".utf8))
        _ = store.writeSkillFile(id: skill.id, relativePath: "logo.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0xFE]))

        #expect(store.skillFileText(id: skill.id, relativePath: "notes.md") == "hello")
        #expect(store.skillFileText(id: skill.id, relativePath: "logo.png") == nil)
    }
    @Test func handEditedChainStepTextWithSameUpdatedAtIsReloaded() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let chain = try #require(store.addChain(title: "Ship", steps: [.custom(text: "old text")]))
        let url = directory.appendingPathComponent("Library/prompts/ship.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        try Data(text.replacingOccurrences(of: "old text", with: "new text").utf8).write(to: url)

        store.reloadFromDiskIfChanged()

        #expect(store.chains.first { $0.id == chain.id }?.steps == [.custom(text: "new text")])
    }

    @Test func updateChainReportsFailureWhenChainIsGone() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let chain = try #require(store.addChain(title: "Ship", steps: [.custom(text: "x")]))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("Library/prompts/ship.md"))

        #expect(throws: LibraryRepositoryError.self) {
            try store.updateChain(id: chain.id, title: "Ship", steps: [.custom(text: "edited")])
        }
    }
}
