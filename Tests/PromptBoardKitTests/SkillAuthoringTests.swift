import Foundation
import Testing
@testable import PromptBoardKit

struct SkillAuthoringTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardAuthoringTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func targets(claude: URL) -> SyncTargets {
        SyncTargets(claudeSkillsURL: claude, agentsSkillsURL: temporaryDirectory())
    }

    func makeRepository() -> (LibraryRepository, directory: URL, claude: URL) {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        return (LibraryRepository(directoryURL: directory, syncTargets: targets(claude: claude)), directory, claude)
    }

    @Test func createSkillWritesPureFrontmatterSidecarAndLink() throws {
        let (repository, directory, claude) = makeRepository()

        let skill = try repository.createSkill(
            name: "Deploy Runbook", description: "Steps to deploy", group: "Ops", body: "# Deploy"
        )

        #expect(skill.name == "deploy-runbook")
        #expect(skill.description == "Steps to deploy")
        // The returned Skill's group is always nil (readSkill hardcodes it; location is truth,
        // seen via load()). The `group: "Ops"` argument files the skill into skills/Ops/.
        #expect(skill.group == nil)
        #expect(skill.body == "# Deploy")

        let folder = directory.appendingPathComponent("Library/skills/Ops/deploy-runbook")
        let markdown = try String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(markdown.contains("name: deploy-runbook"))
        #expect(markdown.contains("description: Steps to deploy"))
        #expect(!markdown.contains("group:"))
        #expect(!markdown.contains("id:"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".promptboard.json").path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: claude.appendingPathComponent("deploy-runbook").path)) != nil)
    }

    @Test func createSkillLinksIntoBothTargetDirectories() throws {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let agents = temporaryDirectory()
        let repository = LibraryRepository(
            directoryURL: directory,
            syncTargets: SyncTargets(claudeSkillsURL: claude, agentsSkillsURL: agents)
        )

        _ = try repository.createSkill(name: "Deploy Runbook", description: "d", group: nil, body: "# Deploy")

        for target in [claude, agents] {
            #expect((try? FileManager.default.destinationOfSymbolicLink(
                atPath: target.appendingPathComponent("deploy-runbook").path)) != nil)
        }
    }

    @Test func relinkAllSkillsCountsEachSkillOnceNotOncePerTargetDirectory() throws {
        let (repository, _, _) = makeRepository()
        _ = try repository.createSkill(name: "One", description: "d", group: nil, body: "b")
        _ = try repository.createSkill(name: "Two", description: "d", group: nil, body: "b")

        // Each skill links into both targets, so a per-outcome count would report 4.
        #expect(try repository.relinkAllSkills() == 2)
    }

    @Test func createSkillDeDupesFolderNameCaseInsensitively() throws {
        let (repository, _, _) = makeRepository()
        _ = try repository.createSkill(name: "note", description: "one", group: nil, body: "")
        let second = try repository.createSkill(name: "Note", description: "two", group: nil, body: "")
        #expect(second.name == "note-2")
    }

    @Test func updateSkillRewritesFieldsKeepingNameAndID() throws {
        let (repository, _, _) = makeRepository()
        let skill = try repository.createSkill(name: "notes", description: "old", group: nil, body: "# Old")

        let updated = try repository.updateSkill(
            id: skill.id, name: "notes", description: "new desc", group: "G", body: "# New"
        )

        #expect(updated.id == skill.id)
        #expect(updated.name == "notes")
        #expect(updated.description == "new desc")
        // Group is location-derived now; updating a skill at the skills root leaves group nil.
        #expect(updated.group == nil)
        #expect(updated.body == "# New")
    }

    @Test func renamingSkillMovesFolderRelinksAndKeepsID() throws {
        let (repository, directory, claude) = makeRepository()
        let skill = try repository.createSkill(name: "old-name", description: "d", group: nil, body: "# B")

        let renamed = try repository.updateSkill(
            id: skill.id, name: "New Name", description: "d", group: nil, body: "# B"
        )

        #expect(renamed.name == "new-name")
        #expect(renamed.id == skill.id)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library/skills/old-name").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library/skills/new-name").path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: claude.appendingPathComponent("old-name").path)) == nil)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: claude.appendingPathComponent("new-name").path)) != nil)
    }

    @Test func renamingSkillSkipsForeignLinkButStillRenamesFolder() throws {
        let (repository, directory, claude) = makeRepository()
        let foreign = claude.appendingPathComponent("taken")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try Data("real".utf8).write(to: foreign.appendingPathComponent("SKILL.md"))
        let skill = try repository.createSkill(name: "mine", description: "d", group: nil, body: "")

        let renamed = try repository.updateSkill(id: skill.id, name: "taken", description: "d", group: nil, body: "")

        #expect(renamed.name == "taken")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library/skills/taken").path))
        #expect(try String(contentsOf: foreign.appendingPathComponent("SKILL.md"), encoding: .utf8) == "real")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: foreign.path)) == nil)
    }

    @Test func updateSkillThrowsForMissingID() throws {
        let (repository, _, _) = makeRepository()
        #expect(throws: LibraryRepositoryError.self) {
            try repository.updateSkill(id: UUID(), name: "x", description: "y", group: nil, body: "")
        }
    }

    @Test func writeSkillFileCreatesNestedFileAndBumpsUpdatedAt() throws {
        let (repository, directory, _) = makeRepository()
        let skill = try repository.createSkill(name: "toolkit", description: "d", group: nil, body: "")
        let before = skill.updatedAt

        let updated = try repository.writeSkillFile(
            id: skill.id, relativePath: "examples/card.json", data: Data("{}".utf8)
        )

        #expect(updated.files.map(\.relativePath).contains("examples/card.json"))
        #expect(updated.updatedAt >= before)
        let onDisk = directory.appendingPathComponent("Library/skills/toolkit/examples/card.json")
        #expect(try String(contentsOf: onDisk, encoding: .utf8) == "{}")
    }

    @Test func writeSkillFileRefusesReservedAndEscapingPaths() throws {
        let (repository, _, _) = makeRepository()
        let skill = try repository.createSkill(name: "guard", description: "d", group: nil, body: "")
        #expect(throws: LibraryRepositoryError.self) {
            try repository.writeSkillFile(id: skill.id, relativePath: "SKILL.md", data: Data())
        }
        #expect(throws: LibraryRepositoryError.self) {
            try repository.writeSkillFile(id: skill.id, relativePath: ".promptboard.json", data: Data())
        }
        #expect(throws: LibraryRepositoryError.self) {
            try repository.writeSkillFile(id: skill.id, relativePath: "../escape.txt", data: Data())
        }
    }

    @Test func renameThenDeleteSkillFile() throws {
        let (repository, _, _) = makeRepository()
        let skill = try repository.createSkill(name: "files", description: "d", group: nil, body: "")
        _ = try repository.writeSkillFile(id: skill.id, relativePath: "a.txt", data: Data("hi".utf8))

        let renamed = try repository.renameSkillFile(id: skill.id, from: "a.txt", to: "b.txt")
        #expect(renamed.files.map(\.relativePath) == ["b.txt"])

        let deleted = try repository.deleteSkillFile(id: skill.id, relativePath: "b.txt")
        #expect(deleted.files.isEmpty)
    }

    @Test func renameSkillFileThrowsWhenSourceMissing() throws {
        let (repository, _, _) = makeRepository()
        let skill = try repository.createSkill(name: "missing", description: "d", group: nil, body: "")
        #expect(throws: LibraryRepositoryError.self) {
            try repository.renameSkillFile(id: skill.id, from: "nope.txt", to: "yep.txt")
        }
    }
}
