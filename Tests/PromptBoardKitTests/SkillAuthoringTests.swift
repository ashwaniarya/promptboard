import Foundation
import Testing
@testable import PromptBoardKit

struct SkillAuthoringTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardAuthoringTests-\(UUID().uuidString)", isDirectory: true)
    }

    func makeRepository() -> (LibraryRepository, directory: URL, claude: URL) {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        return (LibraryRepository(directoryURL: directory, claudeSkillsURL: claude), directory, claude)
    }

    @Test func createSkillWritesPureFrontmatterSidecarAndLink() throws {
        let (repository, directory, claude) = makeRepository()

        let skill = try repository.createSkill(
            name: "Deploy Runbook", description: "Steps to deploy", group: "Ops", body: "# Deploy"
        )

        #expect(skill.name == "deploy-runbook")
        #expect(skill.description == "Steps to deploy")
        #expect(skill.group == "Ops")
        #expect(skill.body == "# Deploy")

        let folder = directory.appendingPathComponent("Library/skills/deploy-runbook")
        let markdown = try String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(markdown.contains("name: deploy-runbook"))
        #expect(markdown.contains("description: Steps to deploy"))
        #expect(!markdown.contains("group:"))
        #expect(!markdown.contains("id:"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".promptboard.json").path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: claude.appendingPathComponent("deploy-runbook").path)) != nil)
    }

    @Test func createSkillDeDupesFolderNameCaseInsensitively() throws {
        let (repository, _, _) = makeRepository()
        _ = try repository.createSkill(name: "note", description: "one", group: nil, body: "")
        let second = try repository.createSkill(name: "Note", description: "two", group: nil, body: "")
        #expect(second.name == "note-2")
    }
}
