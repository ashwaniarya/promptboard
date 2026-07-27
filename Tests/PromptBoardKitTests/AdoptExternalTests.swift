import Foundation
import Testing
@testable import PromptBoardKit

struct AdoptExternalTests {
    private func makeRepository() -> LibraryRepository {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AdoptTests-\(UUID().uuidString)", isDirectory: true)
        return LibraryRepository(directoryURL: directory, syncTargets: .temporary())
    }

    private func makeExternalSkill(named name: String) throws -> ExternalItem {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AdoptSource-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: original\n---\n\nOriginal body"
            .write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return ExternalItem(name: name, kind: .skill, origin: "Claude Code", url: folder)
    }

    @Test func copyLeavesTheOriginalByteIdentical() throws {
        let repository = makeRepository()
        let item = try makeExternalSkill(named: "trello-card-reader")
        let before = try Data(contentsOf: item.url.appendingPathComponent("SKILL.md"))

        try repository.adoptExternal(item, mode: .copy)

        let after = try Data(contentsOf: item.url.appendingPathComponent("SKILL.md"))
        #expect(before == after)
        #expect(FileManager.default.fileExists(
            atPath: repository.skillsDirectoryURL.appendingPathComponent("trello-card-reader/SKILL.md").path
        ))
    }

    @Test func moveBacksUpTheOriginalAndLeavesAnOwnedLinkInItsPlace() throws {
        let repository = makeRepository()
        let item = try makeExternalSkill(named: "trello-card-reader")

        try repository.adoptExternal(item, mode: .move)

        #expect(SymlinkManager.isOwned(item.url, byStorageRoot: repository.directoryURL))
        let siblings = try FileManager.default.contentsOfDirectory(
            atPath: item.url.deletingLastPathComponent().path
        )
        #expect(siblings.contains { $0.hasPrefix("trello-card-reader.promptboard-backup-") })
    }

    @Test func adoptedSkillBecomesALibraryItem() throws {
        let repository = makeRepository()
        let item = try makeExternalSkill(named: "trello-card-reader")

        try repository.adoptExternal(item, mode: .copy)

        let names = try repository.load().items.compactMap { entry -> String? in
            if case .skill(let skill) = entry { return skill.name } else { return nil }
        }
        #expect(names.contains("trello-card-reader"))
    }

    @Test func adoptingAPromptFileCreatesALibraryPrompt() throws {
        let repository = makeRepository()
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AdoptPrompt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("readability.md")
        try "---\ndescription: tidy up\n---\n\nMake it readable."
            .write(to: file, atomically: true, encoding: .utf8)
        let item = ExternalItem(name: "readability", kind: .prompt, origin: "Claude Code", url: file)

        try repository.adoptExternal(item, mode: .copy)

        let titles = try repository.load().items.compactMap { entry -> String? in
            if case .prompt(let prompt) = entry { return prompt.title } else { return nil }
        }
        #expect(titles.contains("readability"))
    }

    @Test func adoptingRefusesToOverwriteAnExistingLibraryItem() throws {
        let repository = makeRepository()
        _ = try repository.createSkill(name: "trello-card-reader", description: "mine", group: nil, body: "Mine")
        let item = try makeExternalSkill(named: "trello-card-reader")

        #expect(throws: (any Error).self) {
            try repository.adoptExternal(item, mode: .move)
        }
        // The guard fires before any copy, so the original must be pristine.
        let contents = try String(contentsOf: item.url.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(contents.contains("Original body"))
    }

    // A prior prompt already owns the "readability" slug, so adopting another forces
    // addPrompt to de-dup to `readability-2.md`. The recomputed-slug bug would aim the
    // in-place link at `readability.md` — a real file, but the WRONG prompt. Asserting
    // only "resolves to something that exists" can't catch that (the base slug differs
    // from the real file exactly when the base file exists); assert the adopted content.
    @Test func movingAnAdoptedPromptLinksToTheDedupedFileNotACollidingSlug() throws {
        let repository = makeRepository()
        _ = try repository.addPrompt(title: "readability", content: "A different, pre-existing prompt.")
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AdoptPromptMove-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("readability.md")
        try "Make it readable.".write(to: file, atomically: true, encoding: .utf8)
        let item = ExternalItem(name: "readability", kind: .prompt, origin: "Claude Code", url: file)

        try repository.adoptExternal(item, mode: .move)

        #expect(SymlinkManager.isOwned(file, byStorageRoot: repository.directoryURL))
        let resolved = try #require(SymlinkManager.resolvedDestination(of: file))
        #expect(FileManager.default.fileExists(atPath: resolved.path))
        let linked = try String(contentsOf: resolved, encoding: .utf8)
        #expect(linked.contains("Make it readable."))
    }
}
