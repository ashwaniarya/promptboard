import Foundation
import Testing
@testable import PromptBoardKit

struct LibraryRepositoryTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func promptsDir(_ base: URL) -> URL {
        base.appendingPathComponent("Library/prompts", isDirectory: true)
    }

    @Test func loadOnEmptyReturnsNothingAndCreatesNothing() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        let load = try repository.load()

        #expect(load.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func addPromptWritesReadableMarkdownAndLoadsBack() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        let prompt = try repository.addPrompt(title: "Code Review", content: "Review the diff", group: "Coding")

        let fileURL = promptsDir(directory).appendingPathComponent("code-review.md")
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(text.contains("title: Code Review"))
        #expect(!text.contains("group:"))
        #expect(text.contains("Review the diff"))

        let load = try repository.load()
        #expect(load.items.count == 1)
        #expect(load.items.first?.id == prompt.id)
        #expect(load.items.first?.title == "Code Review")
        #expect(load.items.first?.group == nil)
    }

    @Test func slugCollisionsGetDistinctFiles() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        _ = try repository.addPrompt(title: "Dup", content: "a")
        _ = try repository.addPrompt(title: "Dup", content: "b")

        let files = try FileManager.default
            .contentsOfDirectory(atPath: promptsDir(directory).path)
            .sorted()
        #expect(files == ["dup-2.md", "dup.md"])
        #expect(try repository.load().items.count == 2)
    }

    @Test func partialUpdatePreservesOmittedFields() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        let added = try repository.addPrompt(title: "Original", content: "original body")

        let renamed = try repository.updatePrompt(id: added.id, title: "Renamed", content: nil)
        #expect(renamed.title == "Renamed")
        #expect(renamed.content == "original body")
        #expect(renamed.updatedAt >= added.updatedAt)

        #expect(try repository.load().items.first?.title == "Renamed")
    }

    @Test func deleteRemovesTheFile() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        let added = try repository.addPrompt(title: "Bye", content: "x")

        _ = try repository.deletePrompt(id: added.id)

        #expect(try repository.load().items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: promptsDir(directory).appendingPathComponent("bye.md").path))
    }

    @Test func unknownIdThrowsPromptNotFound() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        let ghost = UUID()

        do {
            _ = try repository.updatePrompt(id: ghost, title: "x", content: nil)
            Issue.record("expected promptNotFound")
        } catch LibraryRepositoryError.promptNotFound(let id) {
            #expect(id == ghost)
        }
    }

    @Test func malformedFileIsSkippedNotFatal() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        _ = try repository.addPrompt(title: "Good", content: "ok")
        let badURL = promptsDir(directory).appendingPathComponent("bad.md")
        try Data("---\ntitle: no id here\n---\nbody".utf8).write(to: badURL)

        let load = try repository.load()
        #expect(load.items.count == 1)
        #expect(load.items.first?.title == "Good")
        #expect(load.skippedPaths.contains { $0.hasSuffix("bad.md") })
    }

    @Test func concurrentAddsLoseNoWrites() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        DispatchQueue.concurrentPerform(iterations: 20) { index in
            _ = try? repository.addPrompt(title: "Prompt \(index)", content: "content \(index)")
        }

        #expect(try repository.load().items.count == 20)
    }

    @Test func migratesLegacyPromptsJsonAndBacksItUp() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = [
            Prompt(title: "Legacy A", content: "a"),
            Prompt(title: "Legacy B", content: "b"),
        ]
        try CanonicalJSON.makeEncoder().encode(legacy)
            .write(to: directory.appendingPathComponent("prompts.json"))
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())

        #expect(try repository.migrateLegacyIfNeeded() == true)

        let load = try repository.load()
        #expect(Set(load.items.map(\.title)) == ["Legacy A", "Legacy B"])

        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!entries.contains("prompts.json"))
        #expect(entries.contains { $0.hasPrefix("prompts.json.migrated-") })

        #expect(try repository.migrateLegacyIfNeeded() == false)
    }
}
