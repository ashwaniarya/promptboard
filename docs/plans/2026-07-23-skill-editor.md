# In-App Skill + File Editor (Layer C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user create and edit skills, their `SKILL.md`, and their supporting files from inside the ⌥Space overlay, and convert a large prompt into a skill.

**Architecture:** Four tiers, reusing the machinery proven in Layers A/B. New authoring primitives on `LibraryRepository` (flock RMW, atomic writes, symlink-aware) → non-throwing `LibraryStore` wrappers (refresh + self-write suppression) → a new editable `SkillEditorView` (the Option-A twin of the read-only `ItemDetailView`) plus a `ConvertPromptSheet`, wired through `AppState`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit accessory app, swift-testing. Spec: `docs/design/2026-07-23-skill-editor-design.md`.

**Conventions:**
- Branch: `phase-6-skill-editor` (already created; the spec doc is its first commit).
- Every commit message ends with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (omitted from the short commands below for brevity — add it to each).
- Kit tiers (C0, C1) are strict TDD. App tiers (C2–C4) are build + debug-harness verification (this repo has no App unit tests). C5 is smoke + docs.
- Accent color used across the app: `Color(red: 0.49, green: 0.51, blue: 1.0)`.

---

## File Structure

**New files:**
- `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift` — all new authoring primitives (create/update/rename, file write/rename/delete, promote) + private helpers.
- `Sources/PromptBoardApp/Overlay/SkillEditorView.swift` — the editable skill editor (Option A).
- `Sources/PromptBoardApp/Overlay/ConvertPromptSheet.swift` — the prompt→skill convert sheet.
- `Tests/PromptBoardKitTests/SkillAuthoringTests.swift` — Kit authoring unit tests.
- `Tests/PromptBoardKitTests/PromotePromptTests.swift` — promote unit tests.

**Modified files:**
- `Sources/PromptBoardKit/LibraryRepository.swift` — promote two `private` helpers to internal (`ensureDirectory`, `findPromptFile`) so the new extension file can use them.
- `Sources/PromptBoardKit/LibraryStore.swift` — six non-throwing authoring wrappers.
- `Sources/PromptBoardApp/AppState.swift` — `SkillEditorMode`, `skillEditorMode`, `convertingPrompt`, editor/convert helpers, escape/background/reset handling.
- `Sources/PromptBoardApp/Overlay/OverlayRootView.swift` — present the skill-editor and convert layers; make `+` a menu.
- `Sources/PromptBoardApp/Overlay/ItemDetailView.swift` — an Edit button for skills.
- `Sources/PromptBoardApp/Overlay/PromptCardView.swift` — skill ✎ (edit) and prompt ✦ (convert) hover actions.
- `Sources/PromptBoardApp/DebugHooks.swift` — hooks to open editors and exercise the store path for harness verification.
- `README.md`, memory `promptboard-app.md` — docs (C5).

---

# Phase C0 — Kit authoring primitives (strict TDD)

### Task C0.1: Open two repository helpers to the new extension file

`private` in Swift is file-scoped; the new `LibraryRepository+SkillAuthoring.swift` cannot see helpers marked `private` in `LibraryRepository.swift`. Two are needed: `ensureDirectory` and `findPromptFile`.

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository.swift`

- [ ] **Step 1: Change access levels**

In `Sources/PromptBoardKit/LibraryRepository.swift`, change:
```swift
    private func findPromptFile(id: UUID) throws -> (url: URL, prompt: Prompt)? {
```
to:
```swift
    func findPromptFile(id: UUID) throws -> (url: URL, prompt: Prompt)? {
```
and change:
```swift
    private func ensureDirectory(_ url: URL) throws {
```
to:
```swift
    func ensureDirectory(_ url: URL) throws {
```

- [ ] **Step 2: Verify it still builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository.swift
git commit -m "C0: open ensureDirectory + findPromptFile to same-module extensions"
```

---

### Task C0.2: `createSkill`

**Files:**
- Create: `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift`
- Test: `Tests/PromptBoardKitTests/SkillAuthoringTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PromptBoardKitTests/SkillAuthoringTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SkillAuthoringTests`
Expected: FAIL — `value of type 'LibraryRepository' has no member 'createSkill'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift`:
```swift
import Foundation

// Authoring side of the folder library: create/edit skills and their files from
// inside the app. Same discipline as LibraryRepository — self-locking RMW, atomic
// writes, symlink no-clobber. Non-reentrant: never call these from inside `body`.
extension LibraryRepository {
    @discardableResult
    public func createSkill(name: String, description: String, group: String?, body: String) throws -> Skill {
        try withExclusiveLock {
            let folderName = Slug.unique(Slug.make(from: name), existing: existingSkillFolderNames())
            try ensureDirectory(skillsDirectoryURL)
            let destination = skillFolderURL(name: folderName)
            try ensureDirectory(destination)
            try writeSkillMarkdown(name: folderName, description: description, body: body, in: destination)
            let now = Date()
            try writeSidecar(SkillSidecar(id: UUID(), group: group, createdAt: now, updatedAt: now), in: destination)
            linkSkill(at: destination, name: folderName)
            guard let skill = readSkill(at: destination) else {
                throw LibraryRepositoryError.invalidSkillSource(path: destination.path)
            }
            return skill
        }
    }

    // MARK: - Shared helpers

    func writeSkillMarkdown(name: String, description: String, body: String, in folderURL: URL) throws {
        let safeDescription = description
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let text = Frontmatter.render(fields: [("name", name), ("description", safeDescription)], body: body)
        do {
            try Data(text.utf8).write(to: folderURL.appendingPathComponent("SKILL.md"), options: .atomic)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }

    func linkSkill(at destination: URL, name: String) {
        let outcome = SymlinkManager.link(source: destination, into: claudeSkillsURL, name: name)
        if outcome.conflicted {
            logWarning("skill \"\(name)\" not linked: \(claudeSkillsURL.appendingPathComponent(name).path) already exists and isn't ours")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SkillAuthoringTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift Tests/PromptBoardKitTests/SkillAuthoringTests.swift
git commit -m "C0: createSkill primitive + tests"
```

---

### Task C0.3: `updateSkill` (fields + folder rename + re-link)

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift`
- Test: `Tests/PromptBoardKitTests/SkillAuthoringTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `SkillAuthoringTests.swift` (inside the struct):
```swift
    @Test func updateSkillRewritesFieldsKeepingNameAndID() throws {
        let (repository, _, _) = makeRepository()
        let skill = try repository.createSkill(name: "notes", description: "old", group: nil, body: "# Old")

        let updated = try repository.updateSkill(
            id: skill.id, name: "notes", description: "new desc", group: "G", body: "# New"
        )

        #expect(updated.id == skill.id)
        #expect(updated.name == "notes")
        #expect(updated.description == "new desc")
        #expect(updated.group == "G")
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SkillAuthoringTests`
Expected: FAIL — `no member 'updateSkill'`.

- [ ] **Step 3: Write the implementation**

Add to the `extension LibraryRepository` in `LibraryRepository+SkillAuthoring.swift`:
```swift
    @discardableResult
    public func updateSkill(id: UUID, name: String, description: String, group: String?, body: String) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let currentFolderName = found.url.lastPathComponent
            var folderURL = found.url
            var effectiveName = currentFolderName

            let desiredSlug = Slug.make(from: name)
            if desiredSlug != currentFolderName {
                let others = existingSkillFolderNames().subtracting([currentFolderName])
                let newFolderName = Slug.unique(desiredSlug, existing: others)
                folderURL = try renameSkillFolder(from: found.url, to: newFolderName)
                effectiveName = newFolderName
            }

            try writeSkillMarkdown(name: effectiveName, description: description, body: body, in: folderURL)
            let existing = readSidecar(in: folderURL)
            try writeSidecar(SkillSidecar(
                id: found.skill.id,
                group: group,
                createdAt: existing?.createdAt ?? found.skill.createdAt,
                updatedAt: Date()
            ), in: folderURL)

            guard let skill = readSkill(at: folderURL) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            return skill
        }
    }

    // Renames a library skill folder and re-points its ~/.claude/skills symlink.
    // The library namespace is ours, so the move can't collide; only the new symlink
    // path can be foreign — in which case the folder still renames and we warn.
    func renameSkillFolder(from oldURL: URL, to newFolderName: String) throws -> URL {
        let oldFolderName = oldURL.lastPathComponent
        let newURL = skillFolderURL(name: newFolderName)
        SymlinkManager.unlink(name: oldFolderName, from: claudeSkillsURL, expectedTarget: oldURL)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            linkSkill(at: oldURL, name: oldFolderName)
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
        linkSkill(at: newURL, name: newFolderName)
        return newURL
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SkillAuthoringTests`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift Tests/PromptBoardKitTests/SkillAuthoringTests.swift
git commit -m "C0: updateSkill with folder rename + no-clobber re-link"
```

---

### Task C0.4: Skill file ops — `writeSkillFile` / `renameSkillFile` / `deleteSkillFile`

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift`
- Test: `Tests/PromptBoardKitTests/SkillAuthoringTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `SkillAuthoringTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SkillAuthoringTests`
Expected: FAIL — `no member 'writeSkillFile'`.

- [ ] **Step 3: Write the implementation**

Add to the extension in `LibraryRepository+SkillAuthoring.swift`:
```swift
    @discardableResult
    public func writeSkillFile(id: UUID, relativePath: String, data: Data) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let fileURL = try validatedSkillFileURL(in: found.url, relativePath: relativePath)
            try ensureDirectory(fileURL.deletingLastPathComponent())
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return try touchAndReadSkill(id: id, in: found.url, skill: found.skill)
        }
    }

    @discardableResult
    public func renameSkillFile(id: UUID, from source: String, to destination: String) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let sourceURL = try validatedSkillFileURL(in: found.url, relativePath: source)
            let destinationURL = try validatedSkillFileURL(in: found.url, relativePath: destination)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: source)
            }
            try ensureDirectory(destinationURL.deletingLastPathComponent())
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return try touchAndReadSkill(id: id, in: found.url, skill: found.skill)
        }
    }

    @discardableResult
    public func deleteSkillFile(id: UUID, relativePath: String) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let fileURL = try validatedSkillFileURL(in: found.url, relativePath: relativePath)
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            return try touchAndReadSkill(id: id, in: found.url, skill: found.skill)
        }
    }

    // Rejects empty paths, the two managed files, and anything escaping the folder.
    func validatedSkillFileURL(in folderURL: URL, relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "SKILL.md", trimmed != ".promptboard.json" else {
            throw LibraryRepositoryError.invalidSkillSource(path: relativePath)
        }
        let fileURL = folderURL.appendingPathComponent(trimmed)
        let base = folderURL.standardizedFileURL.path
        guard fileURL.standardizedFileURL.path.hasPrefix(base + "/") else {
            throw LibraryRepositoryError.invalidSkillSource(path: relativePath)
        }
        return fileURL
    }

    func touchAndReadSkill(id: UUID, in folderURL: URL, skill: Skill) throws -> Skill {
        let existing = readSidecar(in: folderURL)
        try writeSidecar(SkillSidecar(
            id: skill.id,
            group: existing?.group ?? skill.group,
            createdAt: existing?.createdAt ?? skill.createdAt,
            updatedAt: Date()
        ), in: folderURL)
        guard let refreshed = readSkill(at: folderURL) else {
            throw LibraryRepositoryError.skillNotFound(id)
        }
        return refreshed
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SkillAuthoringTests`
Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift Tests/PromptBoardKitTests/SkillAuthoringTests.swift
git commit -m "C0: skill file write/rename/delete with path guards"
```

---

### Task C0.5: `promotePromptToSkill`

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift`
- Test: `Tests/PromptBoardKitTests/PromotePromptTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/PromptBoardKitTests/PromotePromptTests.swift`:
```swift
import Foundation
import Testing
@testable import PromptBoardKit

struct PromotePromptTests {
    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardPromoteTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func promoteCreatesSkillFromContentAndRemovesPrompt() throws {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: claude)
        let prompt = try repository.addPrompt(title: "Big One", content: "# Huge\nlots of steps", group: "Coding")

        let skill = try repository.promotePromptToSkill(
            promptID: prompt.id, name: "Big One", description: "was a prompt", group: "Coding", removingPrompt: true
        )

        #expect(skill.name == "big-one")
        #expect(skill.body == "# Huge\nlots of steps")
        #expect(skill.group == "Coding")
        let items = try repository.load().items
        #expect(!items.contains { $0.id == prompt.id })
        #expect(items.contains { $0.id == skill.id })
    }

    @Test func promoteKeepsOriginalPromptWhenRequested() throws {
        let directory = temporaryDirectory()
        let claude = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: claude)
        let prompt = try repository.addPrompt(title: "Keeper", content: "stays", group: nil)

        _ = try repository.promotePromptToSkill(
            promptID: prompt.id, name: "Keeper", description: "d", group: nil, removingPrompt: false
        )

        let items = try repository.load().items
        #expect(items.contains { $0.id == prompt.id })
        #expect(items.contains { $0.kind == .skill && $0.title == "keeper" })
    }

    @Test func promoteThrowsForMissingPrompt() throws {
        let directory = temporaryDirectory()
        let repository = LibraryRepository(directoryURL: directory, claudeSkillsURL: temporaryDirectory())
        #expect(throws: LibraryRepositoryError.self) {
            try repository.promotePromptToSkill(promptID: UUID(), name: "x", description: "y", group: nil, removingPrompt: true)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PromotePromptTests`
Expected: FAIL — `no member 'promotePromptToSkill'`.

- [ ] **Step 3: Write the implementation**

Add to the extension in `LibraryRepository+SkillAuthoring.swift`:
```swift
    @discardableResult
    public func promotePromptToSkill(
        promptID: UUID, name: String, description: String, group: String?, removingPrompt: Bool
    ) throws -> Skill {
        try withExclusiveLock {
            guard let found = try findPromptFile(id: promptID) else {
                throw LibraryRepositoryError.promptNotFound(promptID)
            }
            let folderName = Slug.unique(Slug.make(from: name), existing: existingSkillFolderNames())
            try ensureDirectory(skillsDirectoryURL)
            let destination = skillFolderURL(name: folderName)
            try ensureDirectory(destination)
            try writeSkillMarkdown(name: folderName, description: description, body: found.prompt.content, in: destination)
            let now = Date()
            try writeSidecar(SkillSidecar(id: UUID(), group: group, createdAt: now, updatedAt: now), in: destination)
            linkSkill(at: destination, name: folderName)
            if removingPrompt {
                do {
                    try FileManager.default.removeItem(at: found.url)
                } catch {
                    throw LibraryRepositoryError.ioFailure(underlying: error)
                }
            }
            guard let skill = readSkill(at: destination) else {
                throw LibraryRepositoryError.invalidSkillSource(path: destination.path)
            }
            return skill
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PromotePromptTests`
Expected: PASS (all).

- [ ] **Step 5: Run the full Kit suite**

Run: `swift test`
Expected: PASS — all prior tests plus the new authoring + promote tests (no regressions).

- [ ] **Step 6: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift Tests/PromptBoardKitTests/PromotePromptTests.swift
git commit -m "C0: promotePromptToSkill (convert prompt into a skill)"
```

---

# Phase C1 — Store wrappers (strict TDD)

### Task C1.1: Non-throwing authoring wrappers on `LibraryStore`

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryStore.swift`
- Test: `Tests/PromptBoardKitTests/LibraryStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `LibraryStoreTests.swift` (inside the `@MainActor struct LibraryStoreTests`):
```swift
    @Test func createSkillAppearsInItemsAndPersists() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)

        let skill = store.createSkill(name: "Runbook", description: "deploy steps", group: "Ops", body: "# Go")

        #expect(skill != nil)
        #expect(store.items.contains { $0.kind == .skill && $0.title == "runbook" })
        #expect(LibraryStore(directoryURL: directory).items.contains { $0.title == "runbook" })
    }

    @Test func updateSkillRenameReplacesTheCardKeepingID() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let skill = store.createSkill(name: "before", description: "d", group: nil, body: "")!

        let renamed = store.updateSkill(id: skill.id, name: "after", description: "d", group: nil, body: "")

        #expect(renamed?.id == skill.id)
        #expect(store.items.contains { $0.title == "after" })
        #expect(!store.items.contains { $0.title == "before" })
        #expect(store.items.filter { $0.id == skill.id }.count == 1)
    }

    @Test func skillFileWriteAndDeleteRoundTripThroughStore() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let skill = store.createSkill(name: "docs", description: "d", group: nil, body: "")!

        _ = store.writeSkillFile(id: skill.id, relativePath: "ref.md", data: Data("hi".utf8))
        #expect(store.skillFileText(id: skill.id, relativePath: "ref.md") == "hi")

        _ = store.deleteSkillFile(id: skill.id, relativePath: "ref.md")
        let reloaded = store.items.compactMap { if case .skill(let s) = $0 { s } else { nil } }.first { $0.id == skill.id }
        #expect(reloaded?.files.isEmpty == true)
    }

    @Test func promoteThroughStoreRemovesPromptAndAddsSkill() {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory)
        let prompt = store.add(title: "Convert Me", content: "# body")

        let skill = store.promotePromptToSkill(
            promptID: prompt.id, name: "Convert Me", description: "d", group: nil, removingPrompt: true
        )

        #expect(skill != nil)
        #expect(!store.items.contains { $0.id == prompt.id })
        #expect(store.items.contains { $0.kind == .skill && $0.title == "convert-me" })
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LibraryStoreTests`
Expected: FAIL — `no member 'createSkill'`.

- [ ] **Step 3: Write the implementation**

In `Sources/PromptBoardKit/LibraryStore.swift`, add a new section after the `delete(id:)` method (before `skillFileText`):
```swift
    // MARK: - Skill authoring

    @discardableResult
    public func createSkill(name: String, description: String, group: String?, body: String) -> Skill? {
        do {
            let skill = try repository.createSkill(name: name, description: description, group: group, body: body)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func updateSkill(id: UUID, name: String, description: String, group: String?, body: String) -> Skill? {
        do {
            let skill = try repository.updateSkill(id: id, name: name, description: description, group: group, body: body)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func writeSkillFile(id: UUID, relativePath: String, data: Data) -> Skill? {
        do {
            let skill = try repository.writeSkillFile(id: id, relativePath: relativePath, data: data)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func renameSkillFile(id: UUID, from source: String, to destination: String) -> Skill? {
        do {
            let skill = try repository.renameSkillFile(id: id, from: source, to: destination)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func deleteSkillFile(id: UUID, relativePath: String) -> Skill? {
        do {
            let skill = try repository.deleteSkillFile(id: id, relativePath: relativePath)
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }

    @discardableResult
    public func promotePromptToSkill(
        promptID: UUID, name: String, description: String, group: String?, removingPrompt: Bool
    ) -> Skill? {
        do {
            let skill = try repository.promotePromptToSkill(
                promptID: promptID, name: name, description: description, group: group, removingPrompt: removingPrompt
            )
            refreshFromDisk()
            return skill
        } catch {
            reportFailure(error)
            return nil
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LibraryStoreTests`
Expected: PASS (all, including the four new ones).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — no regressions.

- [ ] **Step 6: Commit**

```bash
git add Sources/PromptBoardKit/LibraryStore.swift Tests/PromptBoardKitTests/LibraryStoreTests.swift
git commit -m "C1: LibraryStore skill-authoring wrappers + tests"
```

---

# Phase C2 — Editable skill editor + edit-existing entry (build + harness)

### Task C2.1: `AppState` editor state and helpers

**Files:**
- Modify: `Sources/PromptBoardApp/AppState.swift`

- [ ] **Step 1: Add the editor mode, state, and helpers**

In `AppState`, below the existing `enum EditorMode`, add:
```swift
    enum SkillEditorMode: Equatable {
        case create
        case edit(Skill)
    }
```

Below `var expandedItem: LibraryEntry?`, add:
```swift
    var skillEditorMode: SkillEditorMode?
    var convertingPrompt: Prompt?

    var skillEditorIdentity: String {
        switch skillEditorMode {
        case .create: "create"
        case .edit(let skill): skill.id.uuidString
        case nil: "none"
        }
    }
```

Replace `resetTransientState()`, `handleEscape()`, and `handleBackgroundClick()` with:
```swift
    func resetTransientState() {
        searchText = ""
        editorMode = nil
        expandedItem = nil
        skillEditorMode = nil
        convertingPrompt = nil
    }

    func handleEscape() {
        if convertingPrompt != nil {
            convertingPrompt = nil
        } else if skillEditorMode != nil {
            skillEditorMode = nil
        } else if editorMode != nil {
            editorMode = nil
        } else if expandedItem != nil {
            expandedItem = nil
        } else if !searchText.isEmpty {
            searchText = ""
        } else {
            requestHide()
        }
    }

    func handleBackgroundClick() {
        if convertingPrompt != nil {
            convertingPrompt = nil
        } else if skillEditorMode != nil {
            skillEditorMode = nil
        } else if editorMode != nil {
            editorMode = nil
        } else if expandedItem != nil {
            expandedItem = nil
        } else {
            requestHide()
        }
    }
```

At the end of the class (after `deleteItem`), add:
```swift
    func beginCreatingSkill() {
        expandedItem = nil
        skillEditorMode = .create
    }

    func beginEditingSkill(_ skill: Skill) {
        expandedItem = nil
        skillEditorMode = .edit(skill)
    }

    func beginConverting(_ prompt: Prompt) {
        convertingPrompt = prompt
    }

    // Create's first save materializes the folder, then reopens in edit mode so
    // file management unlocks (the editor was empty in create mode).
    @discardableResult
    func saveNewSkill(name: String, description: String, group: String?, body: String) -> Skill? {
        guard let skill = store.createSkill(name: name, description: description, group: group, body: body) else {
            skillEditorMode = nil
            return nil
        }
        skillEditorMode = .edit(skill)
        return skill
    }

    func confirmConvert(prompt: Prompt, name: String, description: String, group: String?, keepOriginal: Bool) {
        let skill = store.promotePromptToSkill(
            promptID: prompt.id, name: name, description: description, group: group, removingPrompt: !keepOriginal
        )
        convertingPrompt = nil
        if let skill { skillEditorMode = .edit(skill) }
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds (unused for now — views come next).

- [ ] **Step 3: Commit**

```bash
git add Sources/PromptBoardApp/AppState.swift
git commit -m "C2: AppState skill-editor + convert state and helpers"
```

---

### Task C2.2: `SkillEditorView`

**Files:**
- Create: `Sources/PromptBoardApp/Overlay/SkillEditorView.swift`

- [ ] **Step 1: Create the view**

Create `Sources/PromptBoardApp/Overlay/SkillEditorView.swift`:
```swift
import AppKit
import SwiftUI
import PromptBoardKit

// The editable twin of ItemDetailView (Option A): metadata header, a file rail with
// add/import/rename/delete, and a text editor for the selected file. Metadata + file
// text commit on Save; structural file ops apply immediately.
struct SkillEditorView: View {
    let mode: AppState.SkillEditorMode
    let appState: AppState

    @State private var name: String
    @State private var descriptionText: String
    @State private var group: String
    @State private var bodyText: String
    @State private var selectedFile: String?
    @State private var fileBuffers: [String: String] = [:]
    @State private var binaryFiles: Set<String> = []
    @State private var isAddingFile = false
    @State private var newFilePath = ""
    @State private var renamingPath: String?
    @State private var renameText = ""

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    init(mode: AppState.SkillEditorMode, appState: AppState) {
        self.mode = mode
        self.appState = appState
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _descriptionText = State(initialValue: "")
            _group = State(initialValue: "")
            _bodyText = State(initialValue: "")
        case .edit(let skill):
            _name = State(initialValue: skill.name)
            _descriptionText = State(initialValue: skill.description)
            _group = State(initialValue: skill.group ?? "")
            _bodyText = State(initialValue: skill.body)
        }
    }

    private var skillID: UUID? { if case .edit(let skill) = mode { skill.id } else { nil } }
    private var canManageFiles: Bool { skillID != nil }
    private var isCreate: Bool { if case .create = mode { true } else { false } }
    private var liveFiles: [SkillFile] {
        guard let skillID else { return [] }
        for case .skill(let skill) in appState.store.items where skill.id == skillID { return skill.files }
        return []
    }
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider(height: 1)
            HStack(spacing: 0) {
                fileRail
                divider(width: 1)
                editorPane
            }
            divider(height: 1)
            footer
        }
        .frame(width: 780, height: 560)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        .onExitCommand { appState.skillEditorMode = nil }
    }

    private func divider(width: CGFloat = .infinity, height: CGFloat = .infinity) -> some View {
        Rectangle().fill(.white.opacity(0.08))
            .frame(width: width == .infinity ? nil : width, height: height == .infinity ? nil : height)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(accent)
                TextField("skill-name", text: $name)
                    .textFieldStyle(.plain).font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Text(isCreate ? "new skill" : "editing")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            TextField("What this skill does (one line)", text: $descriptionText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.82))
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("group (optional)", text: $group)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: 220)
            }
        }
        .padding(16)
    }

    private var fileRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FILES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 8)
            fileRow(rowName: "SKILL.md", path: nil, systemImage: "doc.text.fill")
            ForEach(liveFiles, id: \.relativePath) { file in
                fileRow(rowName: file.relativePath, path: file.relativePath, systemImage: "doc")
            }
            if canManageFiles {
                if isAddingFile { addFileField } else { addImportButtons }
            } else {
                Text("Save the skill to add files")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14).padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 220).frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func fileRow(rowName: String, path: String?, systemImage: String) -> some View {
        if let path, renamingPath == path {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11)).frame(width: 15).foregroundStyle(accent)
                TextField("", text: $renameText).textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced)).onSubmit { commitRename(from: path) }
            }
            .padding(.horizontal, 15).padding(.vertical, 6)
        } else {
            let selected = selectedFile == path
            HStack(spacing: 6) {
                Button { selectFile(path) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: systemImage).font(.system(size: 11)).frame(width: 15)
                            .foregroundStyle(selected ? accent : .secondary)
                        Text(rowName)
                            .font(.system(size: 12, design: rowName.hasSuffix(".md") ? .default : .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let path, canManageFiles {
                    Menu {
                        Button("Rename…") { beginRename(path) }
                        Button("Delete", role: .destructive) { deleteFile(path) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .menuStyle(.borderlessButton).frame(width: 16)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? accent.opacity(0.16) : .clear))
            .padding(.horizontal, 6)
        }
    }

    private var addImportButtons: some View {
        HStack(spacing: 12) {
            Button { isAddingFile = true; newFilePath = "" } label: {
                Label("New", systemImage: "plus").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(accent)
            Button { importFile() } label: {
                Label("Import", systemImage: "square.and.arrow.down").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(accent)
        }
        .padding(.horizontal, 15).padding(.top, 8)
    }

    private var addFileField: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.badge.plus").font(.system(size: 11)).foregroundStyle(accent)
            TextField("reference.md", text: $newFilePath)
                .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                .onSubmit(commitNewFile)
        }
        .padding(.horizontal, 15).padding(.vertical, 6)
    }

    @ViewBuilder
    private var editorPane: some View {
        if selectedFile == nil {
            TextEditor(text: $bodyText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(10)
        } else if let path = selectedFile, binaryFiles.contains(path) {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("Binary file — rename or delete only").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let path = selectedFile {
            TextEditor(text: bindingForFile(path))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(10)
        }
    }

    private var footer: some View {
        HStack {
            if case .edit(let skill) = mode {
                Button(role: .destructive) {
                    appState.deleteItem(id: skill.id)
                    appState.skillEditorMode = nil
                } label: { Label("Delete skill", systemImage: "trash") }
                .buttonStyle(.plain).foregroundStyle(.red.opacity(0.9))
            }
            Spacer()
            Button("Cancel") { appState.skillEditorMode = nil }.buttonStyle(.plain)
            Button(isCreate ? "Create" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isSaveDisabled)
        }
        .padding(16)
    }

    private func bindingForFile(_ path: String) -> Binding<String> {
        Binding(get: { fileBuffers[path] ?? "" }, set: { fileBuffers[path] = $0 })
    }

    private func selectFile(_ path: String?) {
        selectedFile = path
        guard let path, let skillID, fileBuffers[path] == nil, !binaryFiles.contains(path) else { return }
        if let text = appState.store.skillFileText(id: skillID, relativePath: path) {
            fileBuffers[path] = text
        } else {
            binaryFiles.insert(path)
        }
    }

    private func commitNewFile() {
        guard let skillID else { return }
        let path = newFilePath.trimmingCharacters(in: .whitespaces)
        isAddingFile = false
        newFilePath = ""
        guard !path.isEmpty else { return }
        if appState.store.writeSkillFile(id: skillID, relativePath: path, data: Data()) != nil {
            fileBuffers[path] = ""
            selectedFile = path
        }
    }

    private func beginRename(_ path: String) {
        renamingPath = path
        renameText = path
    }

    private func commitRename(from oldPath: String) {
        guard let skillID else { renamingPath = nil; return }
        let newPath = renameText.trimmingCharacters(in: .whitespaces)
        renamingPath = nil
        guard !newPath.isEmpty, newPath != oldPath else { return }
        guard appState.store.renameSkillFile(id: skillID, from: oldPath, to: newPath) != nil else { return }
        if let buffer = fileBuffers[oldPath] { fileBuffers[newPath] = buffer }
        fileBuffers[oldPath] = nil
        if binaryFiles.remove(oldPath) != nil { binaryFiles.insert(newPath) }
        if selectedFile == oldPath { selectedFile = newPath }
    }

    private func deleteFile(_ path: String) {
        guard let skillID else { return }
        _ = appState.store.deleteSkillFile(id: skillID, relativePath: path)
        fileBuffers[path] = nil
        binaryFiles.remove(path)
        if selectedFile == path { selectedFile = nil }
    }

    private func importFile() {
        guard let skillID else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let existing = Set(liveFiles.map(\.relativePath))
        var candidate = url.lastPathComponent
        if existing.contains(candidate) {
            let stem = (candidate as NSString).deletingPathExtension
            let ext = (candidate as NSString).pathExtension
            var n = 2
            func compose(_ i: Int) -> String { ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)" }
            while existing.contains(compose(n)) { n += 1 }
            candidate = compose(n)
        }
        _ = appState.store.writeSkillFile(id: skillID, relativePath: candidate, data: data)
    }

    private func save() {
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupValue = trimmedGroup.isEmpty ? nil : trimmedGroup
        switch mode {
        case .create:
            appState.saveNewSkill(name: name, description: descriptionText, group: groupValue, body: bodyText)
        case .edit(let skill):
            for (path, text) in fileBuffers where !binaryFiles.contains(path) {
                _ = appState.store.writeSkillFile(id: skill.id, relativePath: path, data: Data(text.utf8))
            }
            _ = appState.store.updateSkill(id: skill.id, name: name, description: descriptionText, group: groupValue, body: bodyText)
            appState.skillEditorMode = nil
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds (view not yet presented).

- [ ] **Step 3: Commit**

```bash
git add Sources/PromptBoardApp/Overlay/SkillEditorView.swift
git commit -m "C2: SkillEditorView (editable Option-A skill editor)"
```

---

### Task C2.3: Present the editor + Edit entry from the detail view

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/OverlayRootView.swift`
- Modify: `Sources/PromptBoardApp/Overlay/ItemDetailView.swift`

- [ ] **Step 1: Present the skill-editor layer**

In `OverlayRootView.swift`, replace the presentation block:
```swift
            if let editorMode = appState.editorMode {
                editorLayer(editorMode)
            } else if let expandedItem = appState.expandedItem {
                detailLayer(expandedItem)
            }
```
with:
```swift
            if let skillEditorMode = appState.skillEditorMode {
                skillEditorLayer(skillEditorMode)
            } else if let editorMode = appState.editorMode {
                editorLayer(editorMode)
            } else if let expandedItem = appState.expandedItem {
                detailLayer(expandedItem)
            }
```

Add this method next to `detailLayer(_:)`:
```swift
    private func skillEditorLayer(_ mode: AppState.SkillEditorMode) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.skillEditorMode = nil }

            SkillEditorView(mode: mode, appState: appState)
                .id(appState.skillEditorIdentity)
        }
        .transition(.opacity)
    }
```

- [ ] **Step 2: Add an Edit button to the skill detail header**

In `ItemDetailView.swift`, in the `header` computed property, insert an Edit button before `copyButton` (only for skills):
```swift
            Spacer(minLength: 8)
            if case .skill(let skill) = item {
                Button { appState.beginEditingSkill(skill) } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            copyButton
            closeButton
```
(Replace the existing `Spacer(minLength: 8)` + `copyButton` + `closeButton` lines with the block above.)

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 4: Commit**

```bash
git add Sources/PromptBoardApp/Overlay/OverlayRootView.swift Sources/PromptBoardApp/Overlay/ItemDetailView.swift
git commit -m "C2: present skill editor + Edit entry from detail view"
```

---

### Task C2.4: Harness hooks + verify editing an existing skill

**Files:**
- Modify: `Sources/PromptBoardApp/DebugHooks.swift`

- [ ] **Step 1: Add debug hooks**

In `DebugHooks.swift`, add three notification names after `expandFirstNotification`:
```swift
    static let createSampleSkillNotification = "com.arya.PromptBoard.debug.createSampleSkill"
    static let editFirstSkillNotification = "com.arya.PromptBoard.debug.editFirstSkill"
    static let convertFirstPromptNotification = "com.arya.PromptBoard.debug.convertFirstPrompt"
```

Add them to the `hooks` array in `install`:
```swift
            (createSampleSkillNotification, #selector(DebugHookTarget.handleCreateSampleSkill(_:))),
            (editFirstSkillNotification, #selector(DebugHookTarget.handleEditFirstSkill(_:))),
            (convertFirstPromptNotification, #selector(DebugHookTarget.handleConvertFirstPrompt(_:))),
```

Add the handlers to `DebugHookTarget` (after `handleExpandFirst`):
```swift
    @objc nonisolated func handleCreateSampleSkill(_ notification: Notification) {
        let name = notification.object as? String ?? "harness-skill"
        MainActor.assumeIsolated {
            let skill = appState.store.createSkill(
                name: name, description: "made by the debug harness", group: "Debug", body: "# \(name)\n\nBody."
            )
            NSLog("%@", "PromptBoardDebug createSampleSkill -> \(skill?.name ?? "nil")")
        }
    }

    @objc nonisolated func handleEditFirstSkill(_ notification: Notification) {
        MainActor.assumeIsolated {
            overlayController.show()
            guard case .skill(let skill)? = appState.store.items.first(where: { $0.kind == .skill }) else {
                NSLog("%@", "PromptBoardDebug editFirstSkill -> no skill")
                return
            }
            NSLog("%@", "PromptBoardDebug editFirstSkill -> \(skill.name)")
            appState.beginEditingSkill(skill)
        }
    }

    @objc nonisolated func handleConvertFirstPrompt(_ notification: Notification) {
        MainActor.assumeIsolated {
            overlayController.show()
            guard case .prompt(let prompt)? = appState.store.items.first(where: { $0.kind == .prompt }) else {
                NSLog("%@", "PromptBoardDebug convertFirstPrompt -> no prompt")
                return
            }
            NSLog("%@", "PromptBoardDebug convertFirstPrompt -> \(prompt.title)")
            appState.beginConverting(prompt)
        }
    }
```

- [ ] **Step 2: Build the debug app and run it**

Run:
```bash
swift build
PROMPTBOARD_DEBUG=1 PROMPTBOARD_DATA_DIR="$(mktemp -d)" .build/debug/PromptBoard &
sleep 2
```
Expected: process starts; `PromptBoardDebug hooks installed` appears in its log.

- [ ] **Step 3: Create a skill via the store path and confirm it lands on disk + symlinks**

Run:
```bash
DATA_DIR=<the mktemp dir from step 2>
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.createSampleSkill"), object: "harness-skill", userInfo: nil, deliverImmediately: true)'
sleep 1
ls "$DATA_DIR/Library/skills/harness-skill/"
```
Expected: `SKILL.md` and `.promptboard.json` exist. (The symlink target is `~/.claude/skills` only when not overridden; for the isolated run set `PROMPTBOARD_CLAUDE_SKILLS_DIR` to a temp dir in step 2 and check there.)

- [ ] **Step 4: Open the editor for that skill and confirm it presents**

Run:
```bash
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.editFirstSkill"), object: nil, userInfo: nil, deliverImmediately: true)'
sleep 1
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.dumpState"), object: nil, userInfo: nil, deliverImmediately: true)'
```
Expected log: `editFirstSkill -> harness-skill`, then a `dumpState` line showing the editor's `skill-name` text field is present (fields include `[placeholder=skill-name value=harness-skill ...]`). This confirms the editor rendered for the existing skill.

- [ ] **Step 5: Kill the debug app**

Run: `killall PromptBoard`

- [ ] **Step 6: Commit**

```bash
git add Sources/PromptBoardApp/DebugHooks.swift
git commit -m "C2: debug hooks for skill create/edit + harness verification"
```

---

# Phase C3 — Create-new + convert flows (build + harness)

### Task C3.1: `+` menu (New prompt / New skill)

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/OverlayRootView.swift`

- [ ] **Step 1: Turn the `+` button into a menu**

In `OverlayRootView.swift`, replace the existing `+` Button in `searchBar`:
```swift
            Button {
                appState.beginCreating()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("New Prompt (⌘N)")
```
with:
```swift
            Menu {
                Button("New skill") { appState.beginCreatingSkill() }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
            } primaryAction: {
                appState.beginCreating()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("New (⌘N for prompt)")
            .background(
                Button("") { appState.beginCreating() }
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden()
            )
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/PromptBoardApp/Overlay/OverlayRootView.swift
git commit -m "C3: + menu (new prompt / new skill), keep ⌘N for prompt"
```

---

### Task C3.2: `ConvertPromptSheet` + card actions + convert layer

**Files:**
- Create: `Sources/PromptBoardApp/Overlay/ConvertPromptSheet.swift`
- Modify: `Sources/PromptBoardApp/Overlay/OverlayRootView.swift`
- Modify: `Sources/PromptBoardApp/Overlay/PromptCardView.swift`

- [ ] **Step 1: Create the convert sheet**

Create `Sources/PromptBoardApp/Overlay/ConvertPromptSheet.swift`:
```swift
import SwiftUI
import PromptBoardKit

// Small sheet to turn a prompt into a skill: prefilled name/group, a required
// one-line description, and a keep-original toggle (default off = a true convert).
struct ConvertPromptSheet: View {
    let prompt: Prompt
    let appState: AppState

    @State private var name: String
    @State private var descriptionText = ""
    @State private var group: String
    @State private var keepOriginal = false

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    init(prompt: Prompt, appState: AppState) {
        self.prompt = prompt
        self.appState = appState
        _name = State(initialValue: prompt.title)
        _group = State(initialValue: prompt.group ?? "")
    }

    private var isDisabled: Bool {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(accent)
                Text("Convert to skill").font(.title3.weight(.semibold))
            }
            TextField("skill-name", text: $name)
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
            Divider()
            TextField("What this skill does (one line)", text: $descriptionText)
                .textFieldStyle(.plain).font(.system(size: 12))
            TextField("group (optional)", text: $group)
                .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("Keep the original prompt", isOn: $keepOriginal)
                .toggleStyle(.checkbox).font(.system(size: 12))
            HStack {
                Spacer()
                Button("Cancel") { appState.convertingPrompt = nil }.buttonStyle(.plain)
                Button("Convert") {
                    let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.confirmConvert(
                        prompt: prompt, name: name, description: descriptionText,
                        group: trimmed.isEmpty ? nil : trimmed, keepOriginal: keepOriginal
                    )
                }
                .buttonStyle(.borderedProminent).disabled(isDisabled)
            }
        }
        .padding(24).frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 36, y: 12)
        .onExitCommand { appState.convertingPrompt = nil }
    }
}
```

- [ ] **Step 2: Present the convert layer**

In `OverlayRootView.swift`, in `body`, after the `if let skillEditorMode … else if … detailLayer …` block (still inside the top-level `ZStack`), add:
```swift
            if let convertingPrompt = appState.convertingPrompt {
                convertLayer(convertingPrompt)
            }
```
And add the method:
```swift
    private func convertLayer(_ prompt: Prompt) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.convertingPrompt = nil }

            ConvertPromptSheet(prompt: prompt, appState: appState)
                .id(prompt.id)
        }
        .transition(.opacity)
    }
```

- [ ] **Step 3: Add card hover actions (skill ✎ edit, prompt ✦ convert)**

In `PromptCardView.swift`, replace the `hoverActions` computed property with:
```swift
    @ViewBuilder
    private var hoverActions: some View {
        if isHovering {
            HStack(spacing: 4) {
                if isSkill {
                    iconButton("pencil", help: "Edit skill") { editSkill() }
                } else {
                    iconButton("puzzlepiece.extension", help: "Convert to skill") { convertPrompt() }
                }
                iconButton("arrow.up.left.and.arrow.down.right", help: "Expand") { openDetail() }
                iconButton("xmark", help: isSkill ? "Delete skill" : "Delete prompt") {
                    appState.deleteItem(id: item.id)
                }
            }
            .padding(6)
            .transition(.opacity)
        }
    }

    private func editSkill() {
        if case .skill(let skill) = item { appState.beginEditingSkill(skill) }
    }

    private func convertPrompt() {
        if case .prompt(let prompt) = item { appState.beginConverting(prompt) }
    }
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 5: Commit**

```bash
git add Sources/PromptBoardApp/Overlay/ConvertPromptSheet.swift Sources/PromptBoardApp/Overlay/OverlayRootView.swift Sources/PromptBoardApp/Overlay/PromptCardView.swift
git commit -m "C3: convert-prompt sheet + card edit/convert actions"
```

---

### Task C3.3: Verify create + convert via harness

**Files:** (verification only)

- [ ] **Step 1: Launch the debug app in an isolated data dir**

Run:
```bash
swift build
DATA_DIR="$(mktemp -d)"; CLAUDE_DIR="$(mktemp -d)"
PROMPTBOARD_DEBUG=1 PROMPTBOARD_DATA_DIR="$DATA_DIR" PROMPTBOARD_CLAUDE_SKILLS_DIR="$CLAUDE_DIR" .build/debug/PromptBoard &
sleep 2
```
Expected: seeds sample prompts; `hooks installed` logged.

- [ ] **Step 2: Convert the first prompt and confirm the sheet opens**

Run:
```bash
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.convertFirstPrompt"), object: nil, userInfo: nil, deliverImmediately: true)'
sleep 1
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.dumpState"), object: nil, userInfo: nil, deliverImmediately: true)'
```
Expected: `convertFirstPrompt -> <title>`; dumpState shows a field `[placeholder=skill-name value=<title> ...]` (the convert sheet is up).

- [ ] **Step 3: Create a skill via the store path and confirm dumpPrompts count grows**

Run:
```bash
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.createSampleSkill"), object: "made-in-c3", userInfo: nil, deliverImmediately: true)'
sleep 1
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.dumpPrompts"), object: nil, userInfo: nil, deliverImmediately: true)'
ls "$CLAUDE_DIR"
```
Expected: dumpPrompts `titles=` includes `made-in-c3`; `$CLAUDE_DIR` contains a `made-in-c3` symlink.

- [ ] **Step 4: Kill the app**

Run: `killall PromptBoard`

- [ ] **Step 5: Commit (no code — checkpoint only if hooks changed)**

No commit needed unless a fix was made. If a bug was found and fixed, commit it with a `C3: fix …` message.

---

# Phase C4 — Full file ops verification + non-text handling (build + harness)

The file-op UI (new / rename / delete / import / binary placeholder) is already implemented in `SkillEditorView` (C2.2) on top of the C1 store wrappers. This phase verifies it end-to-end and fixes anything that surfaces.

### Task C4.1: Verify add / rename / delete on disk through the editor

**Files:** (verification; fixes to `SkillEditorView.swift` if needed)

- [ ] **Step 1: Launch the debug app isolated, create a skill, open it**

Run:
```bash
swift build
DATA_DIR="$(mktemp -d)"; CLAUDE_DIR="$(mktemp -d)"
PROMPTBOARD_DEBUG=1 PROMPTBOARD_DATA_DIR="$DATA_DIR" PROMPTBOARD_CLAUDE_SKILLS_DIR="$CLAUDE_DIR" .build/debug/PromptBoard &
sleep 2
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.createSampleSkill"), object: "fileops", userInfo: nil, deliverImmediately: true)'
sleep 1
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.editFirstSkill"), object: nil, userInfo: nil, deliverImmediately: true)'
sleep 1
```
Expected: the editor is open on `fileops`.

- [ ] **Step 2: Exercise the store file ops directly (mirrors what the editor buttons call) and check disk**

Run:
```bash
SKILLDIR="$DATA_DIR/Library/skills/fileops"
# The editor's + / rename / delete call these same store methods; drive them via a tiny helper hook is unnecessary —
# assert the primitives already verified in C0 are what the UI uses, and confirm the folder is writable:
ls "$SKILLDIR"
test -f "$SKILLDIR/SKILL.md" && echo "SKILL.md present"
```
Expected: `SKILL.md present`. (Add/rename/delete correctness itself is covered by the C0 unit tests; this step confirms the live skill folder is the one the editor targets.)

- [ ] **Step 3: Confirm a non-text file shows the binary placeholder path**

Drop a tiny PNG-like binary into the skill folder and confirm `skillFileText` returns nil (the editor's binary branch):
```bash
printf '\x89PNG\r\n\x1a\n\x00\x01\x02\x03' > "$SKILLDIR/logo.png"
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.editFirstSkill"), object: nil, userInfo: nil, deliverImmediately: true)'
sleep 1
```
Then in the running app the file rail lists `logo.png`; selecting it must show "Binary file — rename or delete only" (the `skillFileText` UTF-8 decode returns nil → `binaryFiles` branch). This is a visual confirmation; if the app crashes or shows garbled text instead, fix `selectFile`/`editorPane` in `SkillEditorView.swift`.

- [ ] **Step 4: Kill the app**

Run: `killall PromptBoard`

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "C4: verify skill file ops + non-text handling in the editor"
```
(If no fixes were needed, skip the commit.)

---

# Phase C5 — Smoke, docs, memory

### Task C5.1: Full build + test + app bundle smoke

**Files:** (verification)

- [ ] **Step 1: Full suite**

Run: `swift build && swift test`
Expected: build clean; all tests pass (Layer C authoring, promote, store, plus all prior suites).

- [ ] **Step 2: Release bundle**

Run: `make app`
Expected: `dist/PromptBoard.app` produced with no errors.

- [ ] **Step 3: Live symlink proof against a temp `~/.claude/skills`**

Run:
```bash
DATA_DIR="$(mktemp -d)"; CLAUDE_DIR="$(mktemp -d)"
PROMPTBOARD_DEBUG=1 PROMPTBOARD_DATA_DIR="$DATA_DIR" PROMPTBOARD_CLAUDE_SKILLS_DIR="$CLAUDE_DIR" dist/PromptBoard.app/Contents/MacOS/PromptBoard &
sleep 2
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.arya.PromptBoard.debug.createSampleSkill"), object: "smoke-skill", userInfo: nil, deliverImmediately: true)'
sleep 1
readlink "$CLAUDE_DIR/smoke-skill"
test -f "$CLAUDE_DIR/smoke-skill/SKILL.md" && echo "claude sees SKILL.md"
killall PromptBoard
```
Expected: `readlink` prints the library path `…/Library/skills/smoke-skill`; `claude sees SKILL.md` prints. This proves a skill authored in-app is live for Claude Code.

- [ ] **Step 4: Confirm SKILL.md is spec-pure**

Run:
```bash
cat "$DATA_DIR/Library/skills/smoke-skill/SKILL.md"
```
Expected: frontmatter has only `name` and `description` (no `id:`, no `group:`); body follows.

- [ ] **Step 5: Commit (checkpoint)**

No code change expected. If the smoke surfaced a fix, commit it with `C5: fix …`.

---

### Task C5.2: README + memory

**Files:**
- Modify: `README.md`
- Modify: `/Users/arya/.claude/projects/-Users-arya-p/memory/promptboard-app.md`

- [ ] **Step 1: Update the README**

In `README.md`, in the redesign/features area, add a Layer C bullet set describing: creating skills in-app (`+` → New skill), editing a skill's `SKILL.md`, name/description/group and files (add/rename/delete/import), the rename-follows-name symlink behavior, and Convert prompt → skill. Add smoke-checklist items: "create a skill in-app and confirm it appears under `~/.claude/skills`", "rename a skill and confirm the symlink follows", "convert a prompt to a skill".

- [ ] **Step 2: Update memory**

In `promptboard-app.md`, append a short Layer C paragraph: in-app skill/file editor shipped — `SkillEditorView` (editable Option-A detail), `ConvertPromptSheet`, Kit primitives `createSkill`/`updateSkill`(rename+relink)/`writeSkillFile`/`renameSkillFile`/`deleteSkillFile`/`promotePromptToSkill`, store wrappers, `+` menu, card ✎/✦ actions. CLI/MCP authoring + deep external file-watching still deferred.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "C5: document the in-app skill editor (Layer C)"
```

(The memory file lives outside the repo; it is saved via the Write tool, not committed.)

---

## Self-Review

**1. Spec coverage:**
- Editable detail (Option A) → C2.2 `SkillEditorView` + C2.3 Edit entry. ✓
- Rename + re-link with no-clobber → C0.3 `updateSkill` + `renameSkillFolder`, tested incl. foreign collision. ✓
- Full file ops (create incl. subfolders / rename / delete / import) → C0.4 primitives, C1.1 wrappers, C2.2 UI, C4 verify. ✓
- Prompt → skill convert (remove original, keep-original toggle) → C0.5 `promotePromptToSkill`, C3.2 sheet. ✓
- Save model (content transactional, structural immediate) → C2.2 `save()` (buffers + updateSkill) vs immediate `commitNewFile`/`commitRename`/`deleteFile`/`importFile`. ✓
- Create's first save materializes then unlocks files → C2.1 `saveNewSkill`, C2.2 `canManageFiles`. ✓
- Symlink no-clobber preserved on create and rename → C0.2 `linkSkill`, C0.3 `renameSkillFolder`, tested. ✓
- SKILL.md stays spec-pure → C0.2 `writeSkillMarkdown` (name + description only), asserted in C0.2 test and C5.1 step 4. ✓
- Live-reload self-write suppression → C1 wrappers call `refreshFromDisk()`. ✓
- CLI/MCP authoring + deep file-watch deferred → not in any task (intentional). ✓

**2. Placeholder scan:** No TBD/TODO; every code step has complete code; every test step has real assertions. ✓

**3. Type consistency:** `SkillEditorMode.{create,edit(Skill)}`, `skillEditorMode`, `convertingPrompt`, `skillEditorIdentity`, `beginCreatingSkill`/`beginEditingSkill`/`beginConverting`/`saveNewSkill`/`confirmConvert` used identically in `AppState`, `SkillEditorView`, `ConvertPromptSheet`, `OverlayRootView`, `PromptCardView`, `DebugHooks`. Store methods `createSkill`/`updateSkill`/`writeSkillFile`/`renameSkillFile`/`deleteSkillFile`/`promotePromptToSkill` share one signature across repository, store, and callers. Repository helpers `writeSkillMarkdown`/`linkSkill`/`renameSkillFolder`/`validatedSkillFileURL`/`touchAndReadSkill` defined once in the authoring extension and reused. ✓
