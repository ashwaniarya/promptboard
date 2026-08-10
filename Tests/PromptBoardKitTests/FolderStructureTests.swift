import Foundation
import Testing
@testable import PromptBoardKit

private func tempLibrary() -> LibraryRepository {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("FolderTests-\(UUID().uuidString)", isDirectory: true)
    return LibraryRepository(directoryURL: dir, syncTargets: .temporary())
}

struct FolderStructureTests {
    @Test func loadDiscoversPromptsNestedInSubfolders() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        let workDir = repo.promptsDirectoryURL.appendingPathComponent("Work/ClientA", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let prompt = Prompt(title: "Deploy Notes", content: "body")
        let fields = "---\nid: \(prompt.id.uuidString)\ntitle: Deploy Notes\n---\n"
        try (fields + "body").write(to: workDir.appendingPathComponent("deploy-notes.md"), atomically: true, encoding: .utf8)

        let loaded = try repo.load()

        #expect(loaded.items.count == 1)
        #expect(loaded.items.first?.group == "Work/ClientA")
        #expect(loaded.items.first?.title == "Deploy Notes")
    }

    @Test func loadDiscoversSkillsNestedInSubfoldersWithoutDescendingIntoThem() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        let skillDir = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "---\nname: logo-export\ndescription: d\n---\nbody"
            .write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let assets = skillDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "x".write(to: assets.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let loaded = try repo.load()

        #expect(loaded.items.count == 1)
        #expect(loaded.items.first?.group == "Work")
        #expect(loaded.items.first?.title == "logo-export")
    }
}
