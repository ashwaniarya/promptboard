import Foundation
import Testing
@testable import PromptBoardKit

struct ExternalLibraryScannerTests {
    private func makeDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ExternalScannerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSkill(named name: String, in directory: URL) throws {
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: d\n---\n\nBody"
            .write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    @Test func findsSkillFoldersAndBadgesThemByOrigin() throws {
        let directory = makeDirectory()
        try makeSkill(named: "trello-card-reader", in: directory)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .skill)],
            storageRoot: makeDirectory()
        )

        #expect(items.count == 1)
        #expect(items[0].name == "trello-card-reader")
        #expect(items[0].origin == "Claude Code")
        #expect(items[0].kind == .skill)
    }

    @Test func readsTheSkillDescriptionFromItsFrontmatter() throws {
        let directory = makeDirectory()
        try makeSkill(named: "trello-card-reader", in: directory)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .skill)],
            storageRoot: makeDirectory()
        )

        #expect(items.first?.description == "d")
    }

    @Test func fallsBackToTheFirstBodyLineWhenAPromptHasNoDescription() throws {
        let directory = makeDirectory()
        try "\n\nMake it readable.\nsecond line"
            .write(to: directory.appendingPathComponent("readability.md"), atomically: true, encoding: .utf8)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .prompt)],
            storageRoot: makeDirectory()
        )

        #expect(items.first?.description == "Make it readable.")
    }

    @Test func findsTopLevelMarkdownInCommandRoots() throws {
        let directory = makeDirectory()
        try "Do the thing".write(
            to: directory.appendingPathComponent("readability.md"), atomically: true, encoding: .utf8
        )

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .prompt)],
            storageRoot: makeDirectory()
        )

        #expect(items.map(\.name) == ["readability"])
        #expect(items[0].kind == .prompt)
    }

    @Test func skipsDotEntriesSoCodexSystemCacheIsNeverListed() throws {
        let directory = makeDirectory()
        try makeSkill(named: ".system", in: directory)
        try makeSkill(named: "vercel-deploy", in: directory)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Codex", kind: .skill)],
            storageRoot: makeDirectory()
        )

        #expect(items.map(\.name) == ["vercel-deploy"])
    }

    @Test func skipsOurOwnLinksSoPushedItemsAreNotReportedAsExternal() throws {
        let storage = makeDirectory()
        let source = storage.appendingPathComponent("code-review", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "---\nname: code-review\ndescription: d\n---\n"
            .write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let directory = makeDirectory()
        SymlinkManager.link(source: source, into: [directory], name: "code-review")
        try makeSkill(named: "grill-me", in: directory)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .skill)],
            storageRoot: storage
        )

        #expect(items.map(\.name) == ["grill-me"])
    }

    // Uses a .prompt root deliberately: a dangling *skill* link would also be caught
    // by the SKILL.md existence check below, which would let this test pass even if
    // isOwned mishandled dangling links. A .prompt root's `pathExtension == "md"`
    // check is a pure string test with no filesystem lookup, so this isolates the
    // ownership guard as the only thing standing between a dangling owned link and
    // it leaking through as "external".
    @Test func skipsOwnedLinksEvenWhenTheirSourceHasBeenDeleted() throws {
        let storage = makeDirectory()
        let source = storage.appendingPathComponent("gone.md")
        try "content".write(to: source, atomically: true, encoding: .utf8)
        let directory = makeDirectory()
        SymlinkManager.link(source: source, into: [directory], name: "gone.md")
        try FileManager.default.removeItem(at: source)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .prompt)],
            storageRoot: storage
        )

        #expect(items.isEmpty)
    }

    @Test func scanOrdersEntriesAlphabeticallyWithinARootAndPreservesRootOrderAcrossRoots() throws {
        let first = makeDirectory()
        try makeSkill(named: "zeta", in: first)
        try makeSkill(named: "alpha", in: first)
        let second = makeDirectory()
        try makeSkill(named: "middle", in: second)

        let items = ExternalLibraryScanner.scan(
            roots: [
                .init(url: first, origin: "Claude Code", kind: .skill),
                .init(url: second, origin: "Codex", kind: .skill),
            ],
            storageRoot: makeDirectory()
        )

        #expect(items.map(\.name) == ["alpha", "zeta", "middle"])
    }

    @Test func skipsADirectoryNamedLikeAMarkdownFileInAPromptRoot() throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("weird.md", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "real".write(to: directory.appendingPathComponent("actual.md"), atomically: true, encoding: .utf8)

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Claude Code", kind: .prompt)],
            storageRoot: makeDirectory()
        )

        #expect(items.map(\.name) == ["actual"])
    }

    @Test func skipsFoldersWithoutASkillFile() throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("not-a-skill", isDirectory: true),
            withIntermediateDirectories: true
        )

        let items = ExternalLibraryScanner.scan(
            roots: [.init(url: directory, origin: "Cursor", kind: .skill)],
            storageRoot: makeDirectory()
        )

        #expect(items.isEmpty)
    }

    @Test func defaultRootsCoverEveryToolAndExcludeCursorManagedSkills() {
        let roots = ExternalLibraryScanner.defaultRoots(environment: [:])
        let paths = roots.map(\.url.path)

        #expect(paths.contains { $0.hasSuffix("/.claude/skills") })
        #expect(paths.contains { $0.hasSuffix("/.claude/commands") })
        #expect(paths.contains { $0.hasSuffix("/.agents/skills") })
        #expect(paths.contains { $0.hasSuffix("/.codex/skills") })
        #expect(paths.contains { $0.hasSuffix("/.cursor/skills") })
        #expect(!paths.contains { $0.contains("skills-cursor") })
    }

    @Test func environmentOverrideReplacesTheRootTableAndBadgesEverythingExternal() {
        let roots = ExternalLibraryScanner.defaultRoots(
            environment: ["PROMPTBOARD_EXTERNAL_SCAN_ROOTS": "/tmp/one:/tmp/two"]
        )

        #expect(roots.map(\.url.path) == ["/tmp/one", "/tmp/two"])
        #expect(roots.allSatisfy { $0.origin == "External" })
    }
}
