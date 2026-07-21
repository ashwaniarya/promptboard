import Foundation
import Testing
@testable import PromptBoardKit

struct SkillRepositoryTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardSkillTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSourceSkill(
        name: String,
        description: String,
        body: String = "# Body",
        files: [String: String] = [:]
    ) throws -> URL {
        let source = temporaryDirectory()
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let skillMarkdown = "---\nname: \(name)\ndescription: \(description)\n---\n\n\(body)\n"
        try Data(skillMarkdown.utf8).write(to: source.appendingPathComponent("SKILL.md"))
        for (relativePath, contents) in files {
            let fileURL = source.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL)
        }
        return source
    }

    @Test func importingSkillCopiesLinksAndLoads() throws {
        let directory = temporaryDirectory()
        let claudeSkills = temporaryDirectory()
        let source = try makeSourceSkill(
            name: "demo-skill", description: "A demo", body: "# Demo",
            files: ["reference.md": "ref"]
        )
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: claudeSkills)

        let skill = try repository.importSkill(fromDirectory: source, group: "Tools")

        #expect(skill.name == "demo-skill")
        #expect(skill.group == "Tools")
        #expect(skill.files.map(\.relativePath) == ["reference.md"])

        let skillFolder = directory.appendingPathComponent("Library/skills/demo-skill")
        #expect(FileManager.default.fileExists(atPath: skillFolder.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: skillFolder.appendingPathComponent(".promptboard.json").path))

        let skillMarkdown = try String(contentsOf: skillFolder.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(!skillMarkdown.contains("group:"))
        #expect(!skillMarkdown.contains("id:"))

        let linkPath = claudeSkills.appendingPathComponent("demo-skill").path
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: linkPath)) != nil)

        #expect(try repository.load().items.contains { $0.kind == .skill && $0.title == "demo-skill" })
    }

    @Test func symlinkNeverClobbersAForeignFolder() throws {
        let directory = temporaryDirectory()
        let claudeSkills = temporaryDirectory()
        let foreign = claudeSkills.appendingPathComponent("demo-skill")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        try Data("real user skill".utf8).write(to: foreign.appendingPathComponent("SKILL.md"))

        let source = try makeSourceSkill(name: "demo-skill", description: "clashes")
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: claudeSkills)

        let skill = try repository.importSkill(fromDirectory: source, group: nil)
        #expect(skill.name == "demo-skill")

        #expect(try String(contentsOf: foreign.appendingPathComponent("SKILL.md"), encoding: .utf8) == "real user skill")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: foreign.path)) == nil)
    }

    @Test func deleteSkillRemovesFolderAndOurSymlink() throws {
        let directory = temporaryDirectory()
        let claudeSkills = temporaryDirectory()
        let source = try makeSourceSkill(name: "demo-skill", description: "d")
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: claudeSkills)
        let skill = try repository.importSkill(fromDirectory: source, group: nil)

        _ = try repository.deleteSkill(id: skill.id)

        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("Library/skills/demo-skill").path))
        #expect(!FileManager.default.fileExists(atPath: claudeSkills.appendingPathComponent("demo-skill").path))
        #expect(try repository.load().items.isEmpty)
    }

    @Test func loadReadsSidecarlessSkillWithStableID() throws {
        let directory = temporaryDirectory()
        let folder = directory.appendingPathComponent("Library/skills/manual")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("---\nname: manual\ndescription: Hand dropped\n---\n# Body".utf8)
            .write(to: folder.appendingPathComponent("SKILL.md"))
        let repository = LibraryRepository(directoryURL: directory)

        let first = try repository.load().items
        let second = try repository.load().items

        #expect(first.count == 1)
        #expect(first.first?.kind == .skill)
        #expect(first.first?.title == "manual")
        #expect(first.first?.id == second.first?.id)
    }

    @Test func updateSkillGroupPersistsInSidecar() throws {
        let directory = temporaryDirectory()
        let claudeSkills = temporaryDirectory()
        let source = try makeSourceSkill(name: "demo-skill", description: "d")
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: claudeSkills)
        let skill = try repository.importSkill(fromDirectory: source, group: nil)
        #expect(skill.group == nil)

        let moved = try repository.updateSkillGroup(id: skill.id, group: "Research")
        #expect(moved.group == "Research")
        #expect(moved.id == skill.id)

        let reloaded = try repository.load().items.first { $0.kind == .skill }
        #expect(reloaded?.group == "Research")
    }
}
