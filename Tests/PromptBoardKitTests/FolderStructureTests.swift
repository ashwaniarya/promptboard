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

    @Test func createFolderMakesADirectoryUnderTheCorrectTree() throws {
        let repo = tempLibrary()
        try repo.createFolder(kind: .prompt, path: "Work/ClientA")
        var isDir: ObjCBool = false
        let created = repo.promptsDirectoryURL.appendingPathComponent("Work/ClientA").path
        #expect(FileManager.default.fileExists(atPath: created, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test func createFolderRejectsPathsEscapingTheRoot() throws {
        let repo = tempLibrary()
        #expect(throws: LibraryRepositoryError.self) {
            try repo.createFolder(kind: .prompt, path: "../escape")
        }
    }

    @Test func renameFolderMovesEveryDescendant() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        let old = repo.promptsDirectoryURL.appendingPathComponent("Work/ClientA", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try "---\nid: \(UUID().uuidString)\ntitle: N\n---\nb"
            .write(to: old.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)

        try repo.renameFolder(kind: .prompt, from: "Work/ClientA", to: "Work/ClientB")

        let moved = repo.promptsDirectoryURL.appendingPathComponent("Work/ClientB/n.md").path
        #expect(FileManager.default.fileExists(atPath: moved))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func deleteFolderMovesChildrenUpToTheParent() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        let parent = repo.promptsDirectoryURL.appendingPathComponent("Work", isDirectory: true)
        let doomed = parent.appendingPathComponent("Temp", isDirectory: true)
        try FileManager.default.createDirectory(at: doomed, withIntermediateDirectories: true)
        try "---\nid: \(UUID().uuidString)\ntitle: N\n---\nb"
            .write(to: doomed.appendingPathComponent("n.md"), atomically: true, encoding: .utf8)

        try repo.deleteFolder(kind: .prompt, path: "Work/Temp")

        #expect(FileManager.default.fileExists(atPath: parent.appendingPathComponent("n.md").path))
        #expect(!FileManager.default.fileExists(atPath: doomed.path))
    }
}
