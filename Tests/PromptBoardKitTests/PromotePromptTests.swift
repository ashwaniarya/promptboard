import Foundation
import Testing
@testable import PromptBoardKit

struct PromotePromptTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardPromoteTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func targets(claude: URL) -> SyncTargets {
        SyncTargets(claudeSkillsURL: claude, agentsSkillsURL: temporaryDirectory())
    }

    @Test func promoteCreatesSkillFromContentAndRemovesPrompt() throws {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let repository = LibraryRepository(
            directoryURL: directory,
            syncTargets: targets(claude: claude)
        )
        let prompt = try repository.addPrompt(title: "Big One", content: "# Huge\nlots of steps", group: "Coding")

        let skill = try repository.promotePromptToSkill(
            promptID: prompt.id, name: "Big One", description: "was a prompt", group: "Coding", removingPrompt: true
        )

        #expect(skill.name == "big-one")
        #expect(skill.body == "# Huge\nlots of steps")
        // Group is location-derived now; promoting into the skills root yields group nil.
        #expect(skill.group == nil)
        let items = try repository.load().items
        #expect(!items.contains { $0.id == prompt.id })
        #expect(items.contains { $0.id == skill.id })
    }

    @Test func promoteKeepsOriginalPromptWhenRequested() throws {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let repository = LibraryRepository(
            directoryURL: directory,
            syncTargets: targets(claude: claude)
        )
        let prompt = try repository.addPrompt(title: "Keeper", content: "stays", group: nil)

        _ = try repository.promotePromptToSkill(
            promptID: prompt.id, name: "Keeper", description: "d", group: nil, removingPrompt: false
        )

        let items = try repository.load().items
        #expect(items.contains { $0.id == prompt.id })
        #expect(items.contains { $0.kind == .skill && $0.title == "keeper" })
    }

    @Test func promotingAPromptOverItsOwnExportLinkRepointsInsteadOfTreatingItAsForeign() throws {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: targets(claude: claude))
        let prompt = try repository.addPrompt(title: "Convert Me", content: "body", group: nil)
        // Sync so the prompt's export symlink occupies the slug in the target dir.
        _ = try repository.reconcileSync()
        let link = claude.appendingPathComponent("convert-me")
        let exportPath = repository.exportSkillsURL.appendingPathComponent("convert-me").standardizedFileURL.path
        #expect(SymlinkManager.resolvedDestination(of: link)?.path == exportPath)

        _ = try repository.promotePromptToSkill(
            promptID: prompt.id, name: "Convert Me", description: "d", group: nil, removingPrompt: true
        )

        // The owned stale export link must be repointed to the new authored skill —
        // followable and owned, not left as a false "isn't ours" conflict.
        let resolved = try #require(SymlinkManager.resolvedDestination(of: link))
        #expect(resolved.path == repository.skillsDirectoryURL.appendingPathComponent("convert-me").standardizedFileURL.path)
        #expect(SymlinkManager.isOwned(link, byStorageRoot: repository.directoryURL))
    }

    @Test func promoteThrowsForMissingPrompt() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        #expect(throws: LibraryRepositoryError.self) {
            try repository.promotePromptToSkill(promptID: UUID(), name: "x", description: "y", group: nil, removingPrompt: true)
        }
    }
}
