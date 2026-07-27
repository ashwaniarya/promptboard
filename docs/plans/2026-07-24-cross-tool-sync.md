# Cross-Tool Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync PromptBoard's prompts and skills to Claude Code, Codex, Cursor and OpenCode, and surface the skills already living inside those tools so they can be adopted into the library.

**Architecture:** The library stays the single source of truth. Every entry PromptBoard creates in a tool directory is a **symlink** back into its own storage, so content edits propagate instantly with no sync step and no drift. Two target directories — `~/.agents/skills` and `~/.claude/skills` — cover all four tools. Prompts are rendered into generated skill folders under `Export/`. Ownership is derived from where a symlink points, so there is no manifest file.

**Tech Stack:** Swift 6 (strict concurrency), swift-testing (`import Testing`, `@Test`, `#expect`), SwiftUI + AppKit, SPM.

**Spec:** `docs/design/2026-07-24-cross-tool-sync-design.md`

---

## File Structure

**Kit — new files**

| File | Responsibility |
| --- | --- |
| `Sources/PromptBoardKit/SkillExportRenderer.swift` | Pure: `Prompt` → `SKILL.md` text + `openai.yaml` text. No filesystem. |
| `Sources/PromptBoardKit/SyncTargets.swift` | The two target dirs, env overrides, test factory. |
| `Sources/PromptBoardKit/ExternalLibraryScanner.swift` | Scans tool dirs, applies skip + ownership rules, returns badged items. |
| `Sources/PromptBoardKit/LibraryRepository+Sync.swift` | Export generation, reconcile, stale-link pruning, conflicts. |
| `Sources/PromptBoardKit/LibraryRepository+Adopt.swift` | Adopt an external item by move or copy. |

**Kit — modified**

| File | Change |
| --- | --- |
| `SymlinkManager.swift` | Multi-directory `link`/`unlink`; add `isOwned(_:byStorageRoot:)`. |
| `LibraryRepository.swift` | `claudeSkillsURL` → `syncTargets`, **no default**. |
| `LibraryStore.swift` | Same signature change; sync wrappers; external items. |

**App — modified**

| File | Change |
| --- | --- |
| `Overlay/PromptCardView.swift` | Origin + conflict badges, read-only external treatment. |
| `Overlay/AdoptExternalSheet.swift` (new) | Move/copy dialog. |
| `Overlay/GroupSidebarView.swift` | "Show external" toggle. |
| `AppState.swift` | External items, adopt state. |
| `AppDelegate.swift`, `DebugHooks.swift` | Wiring, new hooks. |

**CLI — modified:** `Sources/PromptBoardCLI/DataDirectoryOptions.swift` (construct `SyncTargets`).

---

## Task 1: SkillExportRenderer — render a prompt as a skill

Pure function, no filesystem. Codex *errors* on an empty `description` and caps `name` at 64 / `description` at 1024; OpenCode *silently skips* a skill with no `name`; a raw colon in a description breaks YAML parsers. All four are encoded here.

**Files:**
- Create: `Sources/PromptBoardKit/SkillExportRenderer.swift`
- Test: `Tests/PromptBoardKitTests/SkillExportRendererTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/SkillExportRendererTests.swift`:

```swift
import Foundation
import Testing
@testable import PromptBoardKit

struct SkillExportRendererTests {
    private func prompt(title: String, content: String = "Body text.") -> Prompt {
        Prompt(title: title, content: content)
    }

    @Test func folderNameIsTheTitleSlug() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.folderName == "code-review")
    }

    @Test func emitsNameDescriptionAndInvocationOptOut() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["name"] == "code-review")
        #expect(document.fields["description"] == "Code Review. Saved PromptBoard prompt, user-invoked only.")
        #expect(document.fields["disable-model-invocation"] == "true")
    }

    @Test func bodyIsCopiedVerbatimWithoutPromptBoardFrontmatter() {
        let export = SkillExportRenderer.render(prompt(title: "Explain", content: "Line one\n\nLine two"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.body == "Line one\n\nLine two")
        #expect(!export.skillMarkdown.contains("createdAt"))
        #expect(!export.skillMarkdown.contains("updatedAt"))
    }

    @Test func descriptionWithColonIsQuotedSoYamlStaysValid() {
        let export = SkillExportRenderer.render(prompt(title: "Ratio: 2:1"))
        #expect(export.skillMarkdown.contains("description: \"Ratio: 2:1. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func descriptionIsNeverEmpty() {
        let export = SkillExportRenderer.render(prompt(title: "   "))
        let document = Frontmatter.parse(export.skillMarkdown)
        let description = try! #require(document.fields["description"])
        #expect(!description.isEmpty)
        #expect(description.hasPrefix("Untitled"))
    }

    @Test func nameIsCappedAtCodexLimit() {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "word ", count: 40)))
        #expect(export.folderName.count <= 64)
        #expect(!export.folderName.hasSuffix("-"))
    }

    @Test func descriptionIsCappedAtCodexLimit() {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "x", count: 2000)))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"]!.count <= 1024)
    }

    @Test func openAIPolicyDisablesImplicitInvocation() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.openAIPolicy.contains("allow_implicit_invocation: false"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SkillExportRendererTests`
Expected: FAIL — `cannot find 'SkillExportRenderer' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/PromptBoardKit/SkillExportRenderer.swift`:

```swift
import Foundation

// Renders a prompt as a minimal Agent Skill. Field rules come from what each tool
// enforces: Codex errors on an empty description and caps name/description length,
// OpenCode silently drops a skill with no name, and an unquoted colon breaks YAML.
public enum SkillExportRenderer {
    public static let nameLimit = 64
    public static let descriptionLimit = 1024

    public struct Export: Equatable, Sendable {
        public let folderName: String
        public let skillMarkdown: String
        public let openAIPolicy: String
    }

    public static func render(_ prompt: Prompt) -> Export {
        let folderName = cappedSlug(from: prompt.title)
        let description = makeDescription(title: prompt.title)
        let markdown = Frontmatter.render(
            fields: [
                ("name", quotedScalar(folderName)),
                ("description", quotedScalar(description)),
                ("disable-model-invocation", "true"),
            ],
            body: prompt.content
        )
        return Export(folderName: folderName, skillMarkdown: markdown, openAIPolicy: openAIPolicy)
    }

    static func cappedSlug(from title: String) -> String {
        let slug = Slug.make(from: title)
        guard slug.count > nameLimit else { return slug }
        var capped = String(slug.prefix(nameLimit))
        while capped.hasSuffix("-") {
            capped.removeLast()
        }
        return capped
    }

    static func makeDescription(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let flattened = base
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return String("\(flattened). Saved PromptBoard prompt, user-invoked only.".prefix(descriptionLimit))
    }

    // Always quote rather than blocklisting unsafe characters. A leading ", [, !, >
    // or a bare `no`/`123` is either invalid YAML or silently reparsed as a bool or
    // number — and a non-string `name` is exactly what makes OpenCode drop a skill.
    // disable-model-invocation stays unquoted because it is a genuine boolean.
    static func quotedScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static let openAIPolicy = """
    policy:
      allow_implicit_invocation: false
    """
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SkillExportRendererTests`
Expected: PASS.

**As built (13 tests):** review of the first cut found that quoting only on `:`/`#`/leading-space still emitted invalid YAML for a title like `[Draft] Blog Post` or one starting with `"`, and silently-wrong YAML for a leading `!` or `>`; separately, a folder name of `no` or `123` parsed as a boolean/integer rather than a string. The always-quote rule above replaced the blocklist, and five regression tests were added for those cases plus a `\r` title.

Assertions on `name` and `description` must read the raw `skillMarkdown`, not `Frontmatter.parse` — that helper splits on the first colon and never unquotes, which is precisely why the original bugs went undetected.

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardKit/SkillExportRenderer.swift Tests/PromptBoardKitTests/SkillExportRendererTests.swift
git commit -m "feat: render prompts as minimal Agent Skills"
```

---

## Task 2: SyncTargets with compiler-enforced isolation

`LibraryRepository.init` currently defaults `claudeSkillsURL` to the **real** `~/.claude/skills`. Layer C leaked four dangling symlinks into it because tests took that default. Adding a second target with a default would reopen the hole, so this task removes the default entirely — every call site must be explicit and the compiler enforces it.

**Files:**
- Create: `Sources/PromptBoardKit/SyncTargets.swift`
- Test: `Tests/PromptBoardKitTests/SyncTargetsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/SyncTargetsTests.swift`:

```swift
import Foundation
import Testing
@testable import PromptBoardKit

struct SyncTargetsTests {
    @Test func agentsDirectoryComesFirstSoCodexCursorOpenCodeAreCoveredFirst() {
        let targets = SyncTargets(
            claudeSkillsURL: URL(fileURLWithPath: "/tmp/claude"),
            agentsSkillsURL: URL(fileURLWithPath: "/tmp/agents")
        )
        #expect(targets.all.map(\.lastPathComponent) == ["agents", "claude"])
    }

    @Test func systemDefaultsPointAtTheTwoCoveringDirectories() {
        let targets = SyncTargets.systemDefault(environment: [:])
        #expect(targets.claudeSkillsURL.path.hasSuffix("/.claude/skills"))
        #expect(targets.agentsSkillsURL.path.hasSuffix("/.agents/skills"))
    }

    @Test func environmentOverridesReplaceEitherDirectory() {
        let targets = SyncTargets.systemDefault(environment: [
            "PROMPTBOARD_CLAUDE_SKILLS_DIR": "/tmp/c",
            "PROMPTBOARD_AGENTS_SKILLS_DIR": "/tmp/a",
        ])
        #expect(targets.claudeSkillsURL.path == "/tmp/c")
        #expect(targets.agentsSkillsURL.path == "/tmp/a")
    }

    @Test func temporaryTargetsAreDistinctAndOutsideTheHomeDirectory() {
        let targets = SyncTargets.temporary()
        #expect(targets.claudeSkillsURL != targets.agentsSkillsURL)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(!targets.claudeSkillsURL.path.hasPrefix(home + "/.claude"))
        #expect(!targets.agentsSkillsURL.path.hasPrefix(home + "/.agents"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncTargetsTests`
Expected: FAIL — `cannot find 'SyncTargets' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/PromptBoardKit/SyncTargets.swift`:

```swift
import Foundation

// The two directories that together reach all four tools: ~/.agents/skills is read
// by Codex, Cursor and OpenCode; ~/.claude/skills is read by Claude Code (and also
// by Cursor and OpenCode). There is deliberately no default initialiser value —
// tests that take a default would write into the user's real tool directories.
public struct SyncTargets: Sendable, Equatable {
    public let claudeSkillsURL: URL
    public let agentsSkillsURL: URL

    public var all: [URL] { [agentsSkillsURL, claudeSkillsURL] }

    public init(claudeSkillsURL: URL, agentsSkillsURL: URL) {
        self.claudeSkillsURL = claudeSkillsURL
        self.agentsSkillsURL = agentsSkillsURL
    }

    public static func systemDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SyncTargets {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func directory(_ key: String, fallback: String) -> URL {
            if let override = environment[key], !override.isEmpty {
                return URL(fileURLWithPath: override, isDirectory: true)
            }
            return home.appendingPathComponent(fallback, isDirectory: true)
        }
        return SyncTargets(
            claudeSkillsURL: directory("PROMPTBOARD_CLAUDE_SKILLS_DIR", fallback: ".claude/skills"),
            agentsSkillsURL: directory("PROMPTBOARD_AGENTS_SKILLS_DIR", fallback: ".agents/skills")
        )
    }

    public static func temporary() -> SyncTargets {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PromptBoardSyncTargets-\(UUID().uuidString)", isDirectory: true)
        return SyncTargets(
            claudeSkillsURL: root.appendingPathComponent("claude", isDirectory: true),
            agentsSkillsURL: root.appendingPathComponent("agents", isDirectory: true)
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncTargetsTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardKit/SyncTargets.swift Tests/PromptBoardKitTests/SyncTargetsTests.swift
git commit -m "feat: add SyncTargets covering both tool skill directories"
```

---

## Task 3: Thread SyncTargets through every construction site

Mechanical but safety-critical. Removing the defaults makes the build fail at every site that was silently using the real directories; fix each one.

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository.swift:19-40`
- Modify: `Sources/PromptBoardKit/LibraryStore.swift:35-38`
- Modify: `Sources/PromptBoardCLI/DataDirectoryOptions.swift:28`
- Modify: `Sources/PromptBoardApp/AppDelegate.swift:23`
- Modify: all five Kit test files that construct a repository or store

- [ ] **Step 1: Change the repository to take SyncTargets with no default**

In `Sources/PromptBoardKit/LibraryRepository.swift`, replace the `claudeSkillsURL` property and initialiser (lines 19 and 32-40) with:

```swift
    public let syncTargets: SyncTargets

    public var claudeSkillsURL: URL { syncTargets.claudeSkillsURL }

    public init(directoryURL: URL, syncTargets: SyncTargets) {
        self.directoryURL = directoryURL
        self.syncTargets = syncTargets
    }
```

Delete `public static var defaultClaudeSkillsURL`. Keeping the computed `claudeSkillsURL` means the existing symlink call sites inside `LibraryRepository.swift:312/350/367` and `LibraryRepository+SkillAuthoring.swift:97/211` keep compiling untouched — Task 4 converts them to multi-directory.

- [ ] **Step 2: Change the store to match**

In `Sources/PromptBoardKit/LibraryStore.swift`, replace lines 35-38 with:

```swift
    public init(directoryURL: URL, syncTargets: SyncTargets) {
        repository = LibraryRepository(directoryURL: directoryURL, syncTargets: syncTargets)
        loadInitial()
    }
```

- [ ] **Step 3: Run the build to enumerate every broken call site**

Run: `swift build 2>&1 | grep -E "error:" | sort -u`
Expected: errors at `DataDirectoryOptions.swift:28`, `AppDelegate.swift:23`, and the test files. Use this list as the checklist for the next two steps.

- [ ] **Step 4: Fix the production call sites**

In `Sources/PromptBoardCLI/DataDirectoryOptions.swift:28`:

```swift
        return LibraryRepository(directoryURL: resolvedDirectoryURL, syncTargets: .systemDefault())
```

In `Sources/PromptBoardApp/AppDelegate.swift:23`:

```swift
        libraryStore = LibraryStore(directoryURL: dataDirectoryURL, syncTargets: .systemDefault())
```

`SyncTargets.systemDefault()` already reads `PROMPTBOARD_CLAUDE_SKILLS_DIR` and `PROMPTBOARD_AGENTS_SKILLS_DIR`, so delete the now-redundant `claudeSkillsURL` env-reading code in `AppDelegate.swift` (the lines that build a URL from `PROMPTBOARD_CLAUDE_SKILLS_DIR`) and any matching helper in `DataDirectoryOptions.swift`.

- [ ] **Step 5: Fix the test call sites**

Add to `Tests/PromptBoardKitTests/LibraryRepositoryTests.swift` (or wherever `temporaryDirectory()` is defined, so all test files share it):

```swift
func isolatedTargets() -> SyncTargets { .temporary() }
```

Then update every construction site:
- `LibraryRepository(directoryURL: directory)` → `LibraryRepository(directoryURL: directory, syncTargets: isolatedTargets())`
- `LibraryRepository(directoryURL: directory, claudeSkillsURL: claude)` → `LibraryRepository(directoryURL: directory, syncTargets: SyncTargets(claudeSkillsURL: claude, agentsSkillsURL: temporaryDirectory()))`
- `LibraryStore(directoryURL: directory)` → `LibraryStore(directoryURL: directory, syncTargets: isolatedTargets())`
- `LibraryStore(directoryURL: directory, claudeSkillsURL: claude)` → `LibraryStore(directoryURL: directory, syncTargets: SyncTargets(claudeSkillsURL: claude, agentsSkillsURL: temporaryDirectory()))`

Files and counts: `LibraryStoreTests.swift` (24), `LibraryRepositoryTests.swift` (9), `SkillRepositoryTests.swift` (5), `PromotePromptTests.swift` (3), `SkillAuthoringTests.swift` (1).

- [ ] **Step 6: Verify the whole suite is green and nothing escaped isolation**

Run: `swift test`
Expected: PASS, 80 tests (76 existing + 4 from Task 2 — Task 1's 8 make 88 once both land; confirm the count only grows).

Then confirm no test wrote into the real directories:

```bash
ls -la ~/.claude/skills ~/.agents/skills
```

Expected: exactly the entries listed in the design doc, no new ones, no dangling links.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: require explicit SyncTargets at every construction site"
```

---

## Task 4: Multi-directory symlinks and the ownership rule

**Files:**
- Modify: `Sources/PromptBoardKit/SymlinkManager.swift`
- Test: `Tests/PromptBoardKitTests/SymlinkManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/SymlinkManagerTests.swift`:

```swift
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

    @Test func linksIntoEveryTargetDirectory() throws {
        let storage = makeDirectory()
        let source = storage.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let first = makeDirectory()
        let second = makeDirectory()

        let outcomes = SymlinkManager.link(source: source, into: [first, second], name: "my-skill")

        #expect(outcomes.allSatisfy(\.linked))
        for directory in [first, second] {
            let path = directory.appendingPathComponent("my-skill").path
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test func aForeignEntryInOneDirectoryConflictsWithoutBlockingTheOther() throws {
        let storage = makeDirectory()
        let source = storage.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
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
        let source = storage.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let ours = makeDirectory()
        let foreign = makeDirectory()
        SymlinkManager.link(source: source, into: [ours], name: "my-skill")
        let foreignFolder = foreign.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: foreignFolder, withIntermediateDirectories: true)

        SymlinkManager.unlink(name: "my-skill", from: [ours, foreign], expectedTarget: source)

        #expect(!FileManager.default.fileExists(atPath: ours.appendingPathComponent("my-skill").path))
        #expect(FileManager.default.fileExists(atPath: foreignFolder.path))
    }

    @Test func isOwnedRecognisesLinksPointingIntoOurStorage() throws {
        let storage = makeDirectory()
        let source = storage.appendingPathComponent("my-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SymlinkManagerTests`
Expected: FAIL — no `link(source:into:name:)` overload taking an array, and no `isOwned`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/PromptBoardKit/SymlinkManager.swift`, inside the `enum`:

```swift
    @discardableResult
    static func link(source: URL, into directories: [URL], name: String) -> [Outcome] {
        directories.map { link(source: source, into: $0, name: name) }
    }

    static func unlink(name: String, from directories: [URL], expectedTarget: URL) {
        for directory in directories {
            unlink(name: name, from: directory, expectedTarget: expectedTarget)
        }
    }

    // Ownership is derived, not recorded: an entry is ours exactly when it is a
    // symlink resolving inside our own storage. That is what lets the external
    // scanner skip our writes without a manifest to keep in step.
    static func isOwned(_ url: URL, byStorageRoot root: URL) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return false
        }
        let resolved = URL(fileURLWithPath: target, relativeTo: url).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        return resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/")
    }
```

`SymlinkManager` is internal, so the tests reach it via `@testable import`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SymlinkManagerTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Point existing skill linking at both directories**

In `LibraryRepository.swift:312` and `:367`, change `into: claudeSkillsURL` to `into: syncTargets.all` and adapt to the returned array:

```swift
            let outcomes = SymlinkManager.link(source: destination, into: syncTargets.all, name: folderName)
            for outcome in outcomes where outcome.conflicted {
                logWarning("skill \"\(folderName)\" not linked in one target: path already exists and isn't ours")
            }
```

In `LibraryRepository.swift:350` and `LibraryRepository+SkillAuthoring.swift:97`, change `from: claudeSkillsURL` to `from: syncTargets.all`. In `LibraryRepository+SkillAuthoring.swift:211`, apply the same change as `:312`.

- [ ] **Step 6: Verify the full suite still passes**

Run: `swift test`
Expected: PASS. Skill-authoring tests now link into both temp dirs.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: link skills into both target directories, derive ownership"
```

---

## Task 5: Export generation and reconcile

**Files:**
- Create: `Sources/PromptBoardKit/LibraryRepository+Sync.swift`
- Test: `Tests/PromptBoardKitTests/SyncReconcileTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/SyncReconcileTests.swift`:

```swift
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
        for directory in targets.all {
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("code-review").path))
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SyncReconcileTests`
Expected: FAIL — `value of type 'LibraryRepository' has no member 'reconcileSync'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/PromptBoardKit/LibraryRepository+Sync.swift`:

```swift
import Foundation

extension LibraryRepository {
    public struct SyncConflict: Sendable, Equatable {
        public let name: String
        public let reason: String
    }

    public var exportURL: URL { directoryURL.appendingPathComponent("Export", isDirectory: true) }
    public var exportSkillsURL: URL { exportURL.appendingPathComponent("skills", isDirectory: true) }

    // Regenerates the prompt exports, links every library item into both target
    // directories, and prunes links we own whose source has gone. Idempotent.
    @discardableResult
    public func reconcileSync() throws -> [SyncConflict] {
        let load = try load()
        var conflicts: [SyncConflict] = []

        // Folder names are the on-disk truth. `Skill.name` comes from SKILL.md and
        // can differ from its folder (collision suffixes, hand edits), so enumerate.
        var skillNames = Set<String>()
        var sources: [String: URL] = [:]
        let skillFolders = (try? FileManager.default.contentsOfDirectory(
            at: skillsDirectoryURL, includingPropertiesForKeys: nil
        )) ?? []
        for folder in skillFolders {
            let name = folder.lastPathComponent
            guard !name.hasPrefix("."),
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent("SKILL.md").path)
            else { continue }
            skillNames.insert(name)
            sources[name] = folder
        }

        try ensureDirectory(exportSkillsURL)
        var exportedNames = Set<String>()
        for case .prompt(let prompt) in load.items {
            let export = SkillExportRenderer.render(prompt)
            guard !skillNames.contains(export.folderName) else {
                conflicts.append(SyncConflict(
                    name: export.folderName,
                    reason: "a skill already uses this name — rename the prompt"
                ))
                continue
            }
            let folder = exportSkillsURL.appendingPathComponent(export.folderName, isDirectory: true)
            try ensureDirectory(folder.appendingPathComponent("agents", isDirectory: true))
            try Data(export.skillMarkdown.utf8)
                .write(to: folder.appendingPathComponent("SKILL.md"), options: .atomic)
            try Data(export.openAIPolicy.utf8)
                .write(to: folder.appendingPathComponent("agents/openai.yaml"), options: .atomic)
            exportedNames.insert(export.folderName)
            sources[export.folderName] = folder
        }

        for name in existingExportNames() where !exportedNames.contains(name) {
            try? FileManager.default.removeItem(at: exportSkillsURL.appendingPathComponent(name))
        }

        for (name, source) in sources {
            for outcome in SymlinkManager.link(source: source, into: syncTargets.all, name: name)
            where outcome.conflicted {
                conflicts.append(SyncConflict(name: name, reason: "a foreign entry already occupies this path"))
            }
        }

        pruneStaleLinks(keeping: Set(sources.keys))
        return conflicts
    }

    private func existingExportNames() -> [String] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: exportSkillsURL, includingPropertiesForKeys: nil
        )
        return (contents ?? []).map(\.lastPathComponent)
    }

    private func pruneStaleLinks(keeping names: Set<String>) {
        for directory in syncTargets.all {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            for entry in contents where SymlinkManager.isOwned(entry, byStorageRoot: directoryURL) {
                guard !names.contains(entry.lastPathComponent) else { continue }
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
```

Note the asymmetry: skills are enumerated from disk (folder names are what the tools actually see), while prompts come from `load()` because their export name is derived from the title, not from a folder.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SyncReconcileTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Call reconcile after every mutation**

In `Sources/PromptBoardKit/LibraryStore.swift`, add to the private section:

```swift
    private func reconcileSync() {
        do {
            syncConflicts = try repository.reconcileSync()
        } catch {
            reportFailure(error)
        }
    }
```

Add the stored property beside `items`:

```swift
    public private(set) var syncConflicts: [LibraryRepository.SyncConflict] = []
```

Then call `reconcileSync()` immediately after each `refreshFromDisk()` inside `refreshFromDisk` itself, so every mutation path picks it up:

```swift
    private func refreshFromDisk() {
        let load = (try? repository.load()) ?? LibraryRepository.Load(items: [], skippedPaths: [])
        items = load.items
        lastSignature = Self.signature(of: load.items)
        reconcileSync()
    }
```

Also call `reconcileSync()` at the end of `loadInitial()` so a launch with no mutations still reconciles.

- [ ] **Step 6: Verify**

Run: `swift test`
Expected: PASS. Watch for store tests that assert exact target-directory contents — prompts now create links there too.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: generate prompt exports and reconcile both target directories"
```

---

## Task 6: ExternalLibraryScanner

**Files:**
- Create: `Sources/PromptBoardKit/ExternalLibraryScanner.swift`
- Test: `Tests/PromptBoardKitTests/ExternalLibraryScannerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/ExternalLibraryScannerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExternalLibraryScannerTests`
Expected: FAIL — `cannot find 'ExternalLibraryScanner' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/PromptBoardKit/ExternalLibraryScanner.swift`:

```swift
import Foundation

public struct ExternalItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case skill
        case prompt
    }

    public var id: String { url.path }
    public let name: String
    public let kind: Kind
    public let origin: String
    public let url: URL
}

// Read-only discovery of skills and commands that already live inside each tool.
// Cursor's managed `skills-cursor` is absent from the root table on purpose (it
// reverts hand edits), and Codex's `.system` cache is caught by the dot-entry rule.
public enum ExternalLibraryScanner {
    public struct Root: Sendable, Equatable {
        public let url: URL
        public let origin: String
        public let kind: ExternalItem.Kind

        public init(url: URL, origin: String, kind: ExternalItem.Kind) {
            self.url = url
            self.origin = origin
            self.kind = kind
        }
    }

    public static func defaultRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [Root] {
        if let raw = environment["PROMPTBOARD_EXTERNAL_SCAN_ROOTS"], !raw.isEmpty {
            return raw.split(separator: ":").map {
                Root(url: URL(fileURLWithPath: String($0), isDirectory: true), origin: "External", kind: .skill)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        func url(_ path: String) -> URL { home.appendingPathComponent(path, isDirectory: true) }
        return [
            Root(url: url(".claude/skills"), origin: "Claude Code", kind: .skill),
            Root(url: url(".claude/commands"), origin: "Claude Code", kind: .prompt),
            Root(url: url(".agents/skills"), origin: "Agents", kind: .skill),
            Root(url: url(".codex/skills"), origin: "Codex", kind: .skill),
            Root(url: url(".cursor/skills"), origin: "Cursor", kind: .skill),
            Root(url: url(".config/opencode/skill"), origin: "OpenCode", kind: .skill),
            Root(url: url(".config/opencode/skills"), origin: "OpenCode", kind: .skill),
            Root(url: url(".config/opencode/command"), origin: "OpenCode", kind: .prompt),
            Root(url: url(".config/opencode/commands"), origin: "OpenCode", kind: .prompt),
        ]
    }

    public static func scan(roots: [Root], storageRoot: URL) -> [ExternalItem] {
        var items: [ExternalItem] = []
        for root in roots {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: root.url, includingPropertiesForKeys: nil
            )) ?? []
            for entry in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = entry.lastPathComponent
                guard !name.hasPrefix("."),
                      !SymlinkManager.isOwned(entry, byStorageRoot: storageRoot) else { continue }
                switch root.kind {
                case .skill:
                    let skillFile = entry.appendingPathComponent("SKILL.md")
                    guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
                    items.append(ExternalItem(name: name, kind: .skill, origin: root.origin, url: entry))
                case .prompt:
                    guard entry.pathExtension == "md" else { continue }
                    items.append(ExternalItem(
                        name: entry.deletingPathExtension().lastPathComponent,
                        kind: .prompt, origin: root.origin, url: entry
                    ))
                }
            }
        }
        return items
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExternalLibraryScannerTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardKit/ExternalLibraryScanner.swift Tests/PromptBoardKitTests/ExternalLibraryScannerTests.swift
git commit -m "feat: discover external skills and commands across tools"
```

---

## Task 7: Adopt an external item by move or copy

**Files:**
- Create: `Sources/PromptBoardKit/LibraryRepository+Adopt.swift`
- Test: `Tests/PromptBoardKitTests/AdoptExternalTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/AdoptExternalTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AdoptExternalTests`
Expected: FAIL — no `adoptExternal`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/PromptBoardKit/LibraryRepository+Adopt.swift`:

```swift
import Foundation

extension LibraryRepository {
    public enum AdoptMode: Sendable, Equatable {
        case move
        case copy
    }

    // Move leaves a link at the original path so a tool that reads only its own
    // directory keeps working; reconcile then links the item into both targets.
    // Adoption goes through createSkill/addPrompt rather than a raw folder copy so
    // the `.promptboard.json` sidecar is written by the same code that owns it.
    public func adoptExternal(_ item: ExternalItem, mode: AdoptMode) throws {
        switch item.kind {
        case .skill:
            try adoptSkill(item, mode: mode)
        case .prompt:
            try adoptPrompt(item, mode: mode)
        }
    }

    private func adoptSkill(_ item: ExternalItem, mode: AdoptMode) throws {
        let folderName = Slug.make(from: item.name)
        let destination = skillsDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LibraryRepositoryError.skillLinkConflict(name: folderName, path: destination.path)
        }

        let text = (try? String(contentsOf: item.url.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
        let document = Frontmatter.parse(text)
        let skill = try createSkill(
            name: folderName,
            description: document.fields["description"] ?? "",
            group: nil,
            body: document.body
        )

        let enumerator = FileManager.default.enumerator(at: item.url, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            let relative = file.path.replacingOccurrences(of: item.url.path + "/", with: "")
            guard relative != "SKILL.md", relative != ".promptboard.json", !relative.hasPrefix("."),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: file)
            else { continue }
            _ = try writeSkillFile(id: skill.id, relativePath: relative, data: data)
        }

        if mode == .move {
            try backUpAndReplaceWithLink(original: item.url, target: destination)
        }
        _ = try reconcileSync()
    }

    private func adoptPrompt(_ item: ExternalItem, mode: AdoptMode) throws {
        let text = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
        let document = Frontmatter.parse(text)
        let prompt = try addPrompt(title: item.name, content: document.body, group: nil)

        if mode == .move {
            let destination = promptsDirectoryURL
                .appendingPathComponent("\(Slug.make(from: prompt.title)).md")
            try backUpAndReplaceWithLink(original: item.url, target: destination)
        }
        _ = try reconcileSync()
    }

    private func backUpAndReplaceWithLink(original: URL, target: URL) throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = original.deletingLastPathComponent()
            .appendingPathComponent("\(original.lastPathComponent).promptboard-backup-\(stamp)")
        try FileManager.default.moveItem(at: original, to: backup)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AdoptExternalTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Add store wrappers**

In `Sources/PromptBoardKit/LibraryStore.swift`, beside the other non-throwing wrappers:

```swift
    public private(set) var externalItems: [ExternalItem] = []

    public func refreshExternalItems(roots: [ExternalLibraryScanner.Root] = ExternalLibraryScanner.defaultRoots()) {
        externalItems = ExternalLibraryScanner.scan(roots: roots, storageRoot: repository.directoryURL)
    }

    @discardableResult
    public func adoptExternal(_ item: ExternalItem, mode: LibraryRepository.AdoptMode) -> Bool {
        do {
            try repository.adoptExternal(item, mode: mode)
            refreshFromDisk()
            refreshExternalItems()
            return true
        } catch {
            reportFailure(error)
            return false
        }
    }
```

Call `refreshExternalItems()` at the end of `loadInitial()`.

- [ ] **Step 6: Verify**

Run: `swift test`
Expected: PASS, full suite.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: adopt external items into the library by move or copy"
```

---

## Task 8: Surface external items in the board

**Files:**
- Create: `Sources/PromptBoardApp/Overlay/AdoptExternalSheet.swift`
- Modify: `Sources/PromptBoardApp/AppState.swift`, `Overlay/LibraryGridView.swift`, `Overlay/PromptCardView.swift`, `Overlay/GroupSidebarView.swift`, `DebugHooks.swift`

There is no App test target, so this task is verified through the debug harness, matching Layers B–D.

- [ ] **Step 1: Add external state to AppState**

In `Sources/PromptBoardApp/AppState.swift`:

```swift
    var showExternalItems = true
    var adoptingItem: ExternalItem?

    var externalItems: [ExternalItem] {
        showExternalItems ? store.externalItems : []
    }

    func beginAdopting(_ item: ExternalItem) {
        adoptingItem = item
    }

    func confirmAdopt(mode: LibraryRepository.AdoptMode) {
        guard let item = adoptingItem else { return }
        store.adoptExternal(item, mode: mode)
        adoptingItem = nil
    }
```

Add `adoptingItem = nil` to the existing escape/background/reset handling alongside `skillEditorMode`.

- [ ] **Step 2: Build the adopt sheet**

Create `Sources/PromptBoardApp/Overlay/AdoptExternalSheet.swift`:

```swift
import PromptBoardKit
import SwiftUI

struct AdoptExternalSheet: View {
    let item: ExternalItem
    let onAdopt: (LibraryRepository.AdoptMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adopt “\(item.name)”")
                .font(.title3.weight(.semibold))
            Text("From \(item.origin) · \(item.url.path)")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Button("Move into library") { onAdopt(.move) }
                Text("Backs up the original, replaces it with a link, and syncs to every tool.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Copy into library") { onAdopt(.copy) }
                Text("Leaves the original untouched. The two copies can drift apart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
```

- [ ] **Step 3: Render external cards with an origin badge**

In `Overlay/LibraryGridView.swift`, append external cards after the library items, passing `isExternal: true` and the origin string into `PromptCardView`. In `PromptCardView.swift`, when `isExternal` is true: dim the card (`.opacity(0.72)`), hide the edit/convert hover buttons, show the origin in a capsule badge, and show an "Adopt" button on hover that calls `appState.beginAdopting(item)`.

Show a conflict badge when `store.syncConflicts` contains an entry whose `name` matches the card's slug, with `reason` as the tooltip.

- [ ] **Step 4: Add the sidebar toggle**

In `Overlay/GroupSidebarView.swift`:

```swift
            Toggle("Show external", isOn: $appState.showExternalItems)
                .toggleStyle(.switch)
                .controlSize(.small)
```

- [ ] **Step 5: Add debug hooks**

In `DebugHooks.swift`, register three observers mirroring the existing ones, all with `suspensionBehavior: .deliverImmediately`:
- `com.arya.PromptBoard.debug.dumpExternal` — logs `externalItems` count, names and origins to stderr.
- `com.arya.PromptBoard.debug.adoptFirstExternal` — object is `"move"` or `"copy"`; adopts the first external item with that mode.
- `com.arya.PromptBoard.debug.dumpSyncConflicts` — logs `store.syncConflicts`.

- [ ] **Step 6: Verify through the harness**

```bash
swift build
PROMPTBOARD_DEBUG=1 \
  PROMPTBOARD_DATA_DIR=/tmp/pb-e5 \
  PROMPTBOARD_CLAUDE_SKILLS_DIR=/tmp/pb-e5-claude \
  PROMPTBOARD_AGENTS_SKILLS_DIR=/tmp/pb-e5-agents \
  ./.build/debug/PromptBoardApp &
```

Then post `dumpExternal` and confirm the log lists your real external skills with correct origin badges. Post `adoptFirstExternal` with `"copy"` and confirm the source file is unchanged.

⚠️ Launch the binary as `.build/debug/PromptBoardApp` — `.build/debug/PromptBoard` is the CLI, which case-collides on APFS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: show external items with origin badges and adopt action"
```

---

## Task 9: Smoke, docs, memory

- [ ] **Step 1: Full green build**

Run: `swift build && swift test`
Expected: PASS, ~107 tests.

- [ ] **Step 2: Resolve the open Cursor symlink question**

This is the one risk the spec deliberately left to empirical test. Build, install, let the app sync, then:

```bash
ls -la ~/.agents/skills ~/.claude/skills
cursor-agent --help >/dev/null 2>&1 && echo "cursor-agent present"
```

Confirm a PromptBoard-created symlink (e.g. `code-review`) exists in both dirs, then start `cursor-agent` and check whether `/code-review` is offered. If Cursor cannot see symlinked skills, add a Cursor-only real-copy mirror into `~/.cursor/skills` — a new `SyncTargets.cursorMirrorURL` written as a directory copy during `reconcileSync`, with its own test. **Only build this if the check fails.**

- [ ] **Step 3: Verify in the other three tools**

```bash
claude --help >/dev/null && echo claude ok
opencode --help >/dev/null && echo opencode ok
```

Start each and confirm a synced prompt appears as `/code-review`. Note in the README any tool where it does not.

- [ ] **Step 4: Install**

```bash
make app
killall PromptBoard 2>/dev/null || true
rm -rf ~/Applications/PromptBoard.app
cp -R dist/PromptBoard.app ~/Applications/
open ~/Applications/PromptBoard.app
```

- [ ] **Step 5: Confirm no stray writes**

```bash
ls -la ~/.claude/skills ~/.agents/skills
find ~/.claude/skills ~/.agents/skills -type l ! -exec test -e {} \; -print
```

Expected: the second command prints nothing — no dangling symlinks, the Layer C failure mode.

- [ ] **Step 6: Update the README**

Add a "Cross-tool sync" section: the two target dirs and why they cover four tools, prompts appearing as `/slug` skills, external items and adopt (move vs copy), the off-limits directories, and the env overrides `PROMPTBOARD_AGENTS_SKILLS_DIR` / `PROMPTBOARD_EXTERNAL_SCAN_ROOTS`. Add smoke items for adopt-move, adopt-copy and conflict badges.

- [ ] **Step 7: Update memory**

Add a Layer E paragraph to `/Users/arya/.claude/projects/-Users-arya-p/memory/promptboard-app.md` covering: the two-dir coverage model, symlink-derived ownership with no manifest, prompts rendered as skills, the off-limits dirs, `SyncTargets` having no default initialiser value on purpose, and whatever the Cursor symlink check concluded.

- [ ] **Step 8: Commit and merge**

```bash
git add -A
git commit -m "docs: cross-tool sync smoke, README and memory"
git checkout main
git merge --no-ff layer-e-cross-tool-sync -m "feat: cross-tool sync for prompts and skills (Layer E)"
```

---

## Self-Review

**Spec coverage:** two-dir targets → Tasks 2, 4; symlinks not copies → Task 4; `Export/` layout and rendering rules → Tasks 1, 5; derived ownership with no manifest → Task 4 (`isOwned`), used in Tasks 5, 6; external discovery with skip rules → Task 6; adopt move/copy with backup → Task 7; collisions and no-clobber (both cases) → Task 5; rename/delete propagation → Tasks 4, 5; sync triggers → Task 5 Step 5; UI (badges, toggle, dialog, conflict badge) → Task 8; quick-insert unchanged → untouched by design; testing tiers → per-task tests plus Task 9; test isolation → Tasks 2, 3; Cursor symlink risk → Task 9 Step 2.

**Type consistency:** `SyncTargets.all` is used in Tasks 4, 5. `SymlinkManager.isOwned(_:byStorageRoot:)` keeps that signature in Tasks 4, 5, 6, 7. `ExternalItem` (`name`, `kind`, `origin`, `url`) is constructed in Task 6 and consumed unchanged in Tasks 7, 8. `LibraryRepository.SyncConflict` uses `name`/`reason` in Tasks 5 and 8. `AdoptMode` is `.move`/`.copy` throughout. `Skill` was checked against `Skill.swift`: it exposes `name` (from SKILL.md), **not** a folder name — so Task 5 enumerates skill folders from disk and Task 7 asserts on `skill.name`. `adoptExternal` returns `Void`, matched by the store wrapper returning `Bool` (Task 7 Step 5) and `AppState.confirmAdopt` ignoring the result (Task 8 Step 1).

**Known gap, deliberately deferred:** the design's "adopted item disappears from the board on move, remains listed on copy" follows automatically from `refreshExternalItems()` — a moved original becomes an owned link and is filtered by the ownership rule, while a copied original still scans as external. No extra task needed.
