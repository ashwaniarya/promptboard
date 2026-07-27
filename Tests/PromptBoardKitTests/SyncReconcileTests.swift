import Foundation
import Testing
@testable import PromptBoardKit

struct SyncReconcileTests {
    private func makeRepository() -> (LibraryRepository, SyncTargets) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SyncReconcileTests-\(UUID().uuidString)", isDirectory: true)
        let targets = SyncTargets.temporary()
        return (LibraryRepository(directoryURL: directory, syncTargets: targets), targets)
    }

    @Test func promptBecomesASkillFolderLinkedIntoBothTargets() throws {
        let (repository, targets) = makeRepository()
        _ = try repository.addPrompt(title: "Code Review", content: "Review it.")

        _ = try repository.reconcileSync()

        let exported = repository.exportSkillsURL.appendingPathComponent("code-review/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: exported.path))
        for directory in targets.all {
            let link = directory.appendingPathComponent("code-review")
            #expect(SymlinkManager.isOwned(link, byStorageRoot: repository.directoryURL))
        }
    }

    // Pins the property that makes it safe to leave Frontmatter.parse non-unquoting:
    // exports are written with quoted YAML scalars, so if load() ever scanned them
    // the quotes would surface in the UI. Export/ sits outside Library/ precisely
    // so that cannot happen.
    @Test func exportedSkillsAreNotPickedUpAsLibraryItems() throws {
        let (repository, _) = makeRepository()
        _ = try repository.addPrompt(title: "Code Review", content: "Review it.")

        _ = try repository.reconcileSync()

        let items = try repository.load().items
        #expect(items.count == 1)
        #expect(items.allSatisfy { if case .prompt = $0 { true } else { false } })
    }

    @Test func codexPolicyFileIsWrittenAlongsideTheSkill() throws {
        let (repository, _) = makeRepository()
        _ = try repository.addPrompt(title: "Code Review", content: "Review it.")

        _ = try repository.reconcileSync()

        let policy = repository.exportSkillsURL.appendingPathComponent("code-review/agents/openai.yaml")
        let text = try String(contentsOf: policy, encoding: .utf8)
        #expect(text.contains("allow_implicit_invocation: false"))
    }

    @Test func reconcileIsIdempotent() throws {
        let (repository, targets) = makeRepository()
        _ = try repository.addPrompt(title: "Code Review", content: "Review it.")

        _ = try repository.reconcileSync()
        let conflicts = try repository.reconcileSync()

        #expect(conflicts.isEmpty)
        let entries = try FileManager.default.contentsOfDirectory(atPath: targets.agentsSkillsURL.path)
        #expect(entries == ["code-review"])
    }

    @Test func deletingAPromptRemovesItsExportAndLinks() throws {
        let (repository, targets) = makeRepository()
        let prompt = try repository.addPrompt(title: "Code Review", content: "Review it.")
        _ = try repository.reconcileSync()

        _ = try repository.deletePrompt(id: prompt.id)
        _ = try repository.reconcileSync()

        let exported = repository.exportSkillsURL.appendingPathComponent("code-review")
        #expect(!FileManager.default.fileExists(atPath: exported.path))
        // Enumerate rather than fileExists: removing the export leaves the link
        // dangling, and fileExists follows symlinks, so it would miss a leaked link.
        for directory in targets.all {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            #expect(!entries.contains("code-review"))
        }
    }

    @Test func foreignEntryAtTheTargetPathIsReportedAndNeverOverwritten() throws {
        let (repository, targets) = makeRepository()
        _ = try repository.addPrompt(title: "Code Review", content: "Review it.")
        let blocking = targets.agentsSkillsURL.appendingPathComponent("code-review", isDirectory: true)
        try FileManager.default.createDirectory(at: blocking, withIntermediateDirectories: true)
        try "not ours".write(to: blocking.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let conflicts = try repository.reconcileSync()

        #expect(conflicts.contains { $0.name == "code-review" })
        let preserved = try String(contentsOf: blocking.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(preserved == "not ours")
    }

    // A slug that migrates from a prompt export to an authored skill (what promoting
    // a prompt does) leaves an owned link aimed at the now-deleted export. Reconcile
    // must repoint it to the skill, not leave it dangling nor cry "foreign" over its
    // own link. Without the repoint the link stays pointed at the vanished export.
    @Test func aSlugMovingFromPromptToSkillRepointsItsLinkNotConflicts() throws {
        let (repository, targets) = makeRepository()
        let prompt = try repository.addPrompt(title: "Code Review", content: "Review it.")
        _ = try repository.reconcileSync()

        _ = try repository.createSkill(name: "code-review", description: "Real skill", group: nil, body: "Body")
        _ = try repository.deletePrompt(id: prompt.id)
        let conflicts = try repository.reconcileSync()

        #expect(conflicts.isEmpty)
        let skillFolder = repository.skillsDirectoryURL
            .appendingPathComponent("code-review").standardizedFileURL.path
        for directory in targets.all {
            let link = directory.appendingPathComponent("code-review")
            #expect(FileManager.default.fileExists(atPath: link.path))
            let destination = try #require(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
            let resolved = URL(fileURLWithPath: destination, relativeTo: link).standardizedFileURL.path
            #expect(resolved == skillFolder)
        }
    }

    @Test func anAuthoredSkillWinsOverAPromptWithTheSameSlug() throws {
        let (repository, _) = makeRepository()
        _ = try repository.createSkill(name: "code-review", description: "Real skill", group: nil, body: "Body")
        _ = try repository.addPrompt(title: "Code Review", content: "Prompt body")

        let conflicts = try repository.reconcileSync()

        #expect(conflicts.contains { $0.name == "code-review" })
        #expect(!FileManager.default.fileExists(
            atPath: repository.exportSkillsURL.appendingPathComponent("code-review").path
        ))
    }
}
