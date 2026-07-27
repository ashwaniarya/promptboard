import Foundation
import Testing
@testable import PromptBoardKit

struct SymlinkManagerTests {
    private func makeDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SymlinkManagerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSource(in storage: URL, named name: String) throws -> URL {
        let source = storage.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return source
    }

    @Test func linksIntoEveryTargetDirectory() throws {
        let storage = makeDirectory()
        let source = try makeSource(in: storage, named: "my-skill")
        let first = makeDirectory()
        let second = makeDirectory()

        let outcomes = SymlinkManager.link(source: source, into: [first, second], name: "my-skill")

        let allLinked = outcomes.allSatisfy(\.linked)
        #expect(allLinked)
        for directory in [first, second] {
            let path = directory.appendingPathComponent("my-skill").path
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil)
        }
    }

    @Test func aForeignEntryInOneDirectoryConflictsWithoutBlockingTheOther() throws {
        let storage = makeDirectory()
        let source = try makeSource(in: storage, named: "my-skill")
        let blocked = makeDirectory()
        let free = makeDirectory()
        try FileManager.default.createDirectory(
            at: blocked.appendingPathComponent("my-skill", isDirectory: true), withIntermediateDirectories: true
        )

        let outcomes = SymlinkManager.link(source: source, into: [blocked, free], name: "my-skill")

        #expect(outcomes.filter(\.conflicted).count == 1)
        #expect(outcomes.filter(\.linked).count == 1)
    }

    @Test func unlinkRemovesOnlyOurOwnLinks() throws {
        let storage = makeDirectory()
        let source = try makeSource(in: storage, named: "my-skill")
        let ours = makeDirectory()
        let foreign = makeDirectory()
        SymlinkManager.link(source: source, into: [ours], name: "my-skill")
        let foreignFolder = foreign.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: foreignFolder, withIntermediateDirectories: true)

        SymlinkManager.unlink(name: "my-skill", from: [ours, foreign], expectedTarget: source)

        #expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: ours.appendingPathComponent("my-skill").path)) == nil)
        #expect(FileManager.default.fileExists(atPath: foreignFolder.path))
    }

    @Test func isOwnedRecognisesLinksPointingIntoOurStorage() throws {
        let storage = makeDirectory()
        let source = try makeSource(in: storage, named: "my-skill")
        let target = makeDirectory()
        SymlinkManager.link(source: source, into: [target], name: "my-skill")

        #expect(SymlinkManager.isOwned(target.appendingPathComponent("my-skill"), byStorageRoot: storage))
    }

    @Test func isOwnedRejectsRealFoldersAndForeignLinks() throws {
        let storage = makeDirectory()
        let elsewhere = makeDirectory()
        let target = makeDirectory()

        let realFolder = target.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: target.appendingPathComponent("foreign"), withDestinationURL: elsewhere
        )

        #expect(!SymlinkManager.isOwned(realFolder, byStorageRoot: storage))
        #expect(!SymlinkManager.isOwned(target.appendingPathComponent("foreign"), byStorageRoot: storage))
    }
}
