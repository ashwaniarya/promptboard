# Nested Folders (Layer F) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users organize prompts and skills into user-created, arbitrarily nested folders that map 1:1 to on-disk directories under `Library/prompts/` and `Library/skills/`, replacing the flat single-label `group` model.

**Architecture:** A folder *is* a directory. An item's folder is derived from where its file/folder lives at scan time — the existing `group: String?` field on `Prompt`/`Skill` is repurposed to hold that derived `/`-separated path (nil at the tree root) instead of a frontmatter label. `load()` and `reconcileSync()` become recursive tree walks; the cross-tool sync *contract* stays flat and slug-keyed (a skill's symlink name is its leaf folder name, unchanged by nesting), and because `LibraryStore` runs `reconcileSync()` after every mutation, reconcile is the single component that re-points every symlink after any move/rename/delete. The sidebar becomes a real expand/collapse tree; moving an item is drag-and-drop only in v1.

**Tech Stack:** Swift 6 / SwiftPM, swift-testing (`@Test`/`#expect`), SwiftUI + AppKit (macOS 14), `FileManager` symlinks. No new dependencies.

---

## Locked plan decisions (read before starting)

These resolve gaps discovered while mapping the approved design onto the real code. They are consistent with the design's contract; flag the user only if you disagree.

1. **The model field stays named `group`.** It is repurposed to hold the derived folder path (e.g. `"Work/ClientA"`, or `nil` at root). Renaming it to `folder` would break the `group` key in the MCP/CLI tools already registered in the user's Claude Code and Codex. `Prompt.group` / `Skill.group` / `LibraryEntry.group` keep their names and types (`String?`). Only App-layer names change (`selectedGroup` → `selectedFolder`, `groupCounts` → `folderTree`).
2. **`group` is now sourced from file location, not frontmatter/sidecar.** `writePrompt` stops emitting a `group:` frontmatter key; the skill sidecar stops carrying `group`. `load()` sets `group` from each item's parent path relative to its tree root. The one-time migration (Task F4) reads the *old* frontmatter/sidecar `group` to decide where to move each item, then that key goes away naturally on next write.
3. **`load()` and `reconcileSync()` walk recursively.** A skill folder is any directory that *directly* contains `SKILL.md`; the walk records it and does not descend into it (its own subdirs are supporting files). The sync symlink name is the leaf folder name — flat and unchanged by nesting.
4. **CLI `--group "Work/ClientA"` files an item into that subfolder.** `addPrompt(group:)` now creates the file under `prompts/<group>/`. This falls out of the same primitive for free and keeps the CLI able to place items; the *app's* "new" flow still passes `group: nil` (creates at root), honoring "no folder picker in editor sheets."
5. **Uniqueness:** a prompt slug / skill leaf-name is made unique against the **global** set of leaf names across the whole tree at create time (the slash-command namespace is flat). A residual cross-folder collision produced by a *move* is caught by the existing `SyncConflict` path — no new mechanism.
6. **Deleting a non-empty folder** moves its direct children (files and subfolders) up to the parent, then removes the now-empty directory. Never cascade-deletes.

## File structure

**Create:**
- `Sources/PromptBoardKit/LibraryRepository+Folders.swift` — folder CRUD + move primitives + the `folderPath(of:underRoot:)` and `folderURL(for:path:)` helpers.
- `Tests/PromptBoardKitTests/FolderStructureTests.swift` — all Kit unit tests for Layer F.
- `Sources/PromptBoardApp/Overlay/FolderTree.swift` — the `FolderNode` tree model built from `[LibraryEntry]`.

**Modify:**
- `Sources/PromptBoardKit/LibraryRepository.swift` — recursive `promptFileURLs()` / `skillFolderURLs()`; `load()` sets `group` from location; `writePrompt` drops the `group` frontmatter key; `readPrompt` stops reading it; `existingPromptSlugs()` / `existingSkillFolderNames()` become tree-wide; `addPrompt` honors a folder path in `group`.
- `Sources/PromptBoardKit/LibraryRepository+Sync.swift` — recursive skill enumeration in `reconcileSync()`.
- `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift` — the skill sidecar no longer round-trips `group`.
- `Sources/PromptBoardKit/LibraryStore.swift` — non-throwing wrappers `createFolder`/`renameFolder`/`deleteFolder`/`moveItem`; one-time folder migration in `loadInitial()`.
- `Sources/PromptBoardApp/AppState.swift` — `selectedFolder`, folder-prefix filter, `folderTree`, move/create-folder actions.
- `Sources/PromptBoardApp/Overlay/GroupSidebarView.swift` — recursive tree rows with expand/collapse + new-folder affordance + drop target.
- `Sources/PromptBoardApp/Overlay/PromptCardView.swift` — `.draggable` carrying the item id.
- `Sources/PromptBoardApp/DebugHooks.swift` — hooks to script folder ops for harness verification.
- `README.md`, `docs/design/...` memory — docs.

---

## Task F0: Recursive scan (prompts + skills read from anywhere in the tree)

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository.swift` (`promptFileURLs()` ~193, `skillFolderURLs()` ~375, `load()` ~50, `existingPromptSlugs()` ~202)
- Test: `Tests/PromptBoardKitTests/FolderStructureTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FolderStructureTests/loadDiscoversPromptsNestedInSubfolders`
Expected: FAIL — `loaded.items` is empty (flat `contentsOfDirectory` never sees `Work/ClientA/deploy-notes.md`).

- [ ] **Step 3: Make `promptFileURLs()` recursive and derive folder in `load()`**

In `LibraryRepository.swift`, replace `promptFileURLs()`:

```swift
    private func promptFileURLs() -> [URL] {
        collectFiles(under: promptsDirectoryURL) { $0.pathExtension == "md" }
    }

    // Recursive walk collecting regular files that pass `include`. Skips dot-entries.
    private func collectFiles(under root: URL, include: (URL) -> Bool) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  include(url) else { continue }
            urls.append(url)
        }
        return urls.sorted { $0.path < $1.path }
    }

    // The `/`-separated folder path of an item relative to its tree root, or nil at root.
    static func folderPath(of itemURL: URL, underRoot root: URL) -> String? {
        let base = root.standardizedFileURL.path
        let parent = itemURL.deletingLastPathComponent().standardizedFileURL.path
        guard parent == base || parent.hasPrefix(base + "/") else { return nil }
        if parent == base { return nil }
        return String(parent.dropFirst(base.count + 1))
    }
```

Update `load()` to stamp the derived folder:

```swift
    public func load() throws -> Load {
        var items: [LibraryEntry] = []
        var skipped: [String] = []
        for url in promptFileURLs() {
            if var prompt = readPrompt(at: url) {
                prompt.group = Self.folderPath(of: url, underRoot: promptsDirectoryURL)
                items.append(.prompt(prompt))
            } else {
                skipped.append(url.path)
            }
        }
        for folderURL in skillFolderURLs() {
            if var skill = readSkill(at: folderURL) {
                skill.group = Self.folderPath(of: folderURL, underRoot: skillsDirectoryURL)
                items.append(.skill(skill))
            } else {
                skipped.append(folderURL.path)
            }
        }
        return Load(items: items, skippedPaths: skipped)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FolderStructureTests/loadDiscoversPromptsNestedInSubfolders`
Expected: PASS.

- [ ] **Step 5: Write the skill-nesting failing test**

Add to `FolderStructureTests`:

```swift
    @Test func loadDiscoversSkillsNestedInSubfoldersWithoutDescendingIntoThem() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        let skillDir = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try "---\nname: logo-export\ndescription: d\n---\nbody"
            .write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        // A nested supporting dir that itself has no SKILL.md must not be mistaken for a skill.
        let assets = skillDir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "x".write(to: assets.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let loaded = try repo.load()

        #expect(loaded.items.count == 1)
        #expect(loaded.items.first?.group == "Work")
        #expect(loaded.items.first?.title == "logo-export")
    }
```

- [ ] **Step 6: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/loadDiscoversSkillsNestedInSubfoldersWithoutDescendingIntoThem`
Expected: FAIL — flat `skillFolderURLs()` returns `Work` (no SKILL.md) and misses `Work/logo-export`.

- [ ] **Step 7: Make `skillFolderURLs()` a recursive leaf-walk**

Replace `skillFolderURLs()`:

```swift
    // A skill folder is any directory that DIRECTLY contains SKILL.md. We record it
    // and do not descend (its subdirs are supporting files, not nested skills).
    func skillFolderURLs() -> [URL] {
        var results: [URL] = []
        func walk(_ dir: URL) {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { return }
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !entry.lastPathComponent.hasPrefix("."),
                      (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                if FileManager.default.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path) {
                    results.append(entry)
                } else {
                    walk(entry)
                }
            }
        }
        walk(skillsDirectoryURL)
        return results.sorted { $0.path < $1.path }
    }
```

- [ ] **Step 8: Run to verify it passes**

Run: `swift test --filter FolderStructureTests/loadDiscoversSkillsNestedInSubfoldersWithoutDescendingIntoThem`
Expected: PASS.

- [ ] **Step 9: Make slug-uniqueness tree-wide + stop persisting `group` in frontmatter**

In `existingPromptSlugs()`, the recursion now returns nested files, so leaf names collide correctly across folders — but two folders can legitimately hold the same leaf. Keep it as the set of *leaf* names (drives create-at-root uniqueness and flags the flat namespace):

```swift
    private func existingPromptSlugs() -> Set<String> {
        Set(promptFileURLs().map { $0.deletingPathExtension().lastPathComponent })
    }
```

(No change needed — it already maps `lastPathComponent`; the recursion just makes it tree-wide.)

In `writePrompt`, remove the `group` frontmatter block so location is the sole source of truth:

```swift
    private func writePrompt(_ prompt: Prompt, to url: URL) throws {
        let fields: [(String, String)] = [
            ("id", prompt.id.uuidString),
            ("title", prompt.title),
            ("createdAt", CanonicalJSON.isoString(from: prompt.createdAt)),
            ("updatedAt", CanonicalJSON.isoString(from: prompt.updatedAt)),
        ]
        let text = Frontmatter.render(fields: fields, body: prompt.content)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw LibraryRepositoryError.ioFailure(underlying: error)
        }
    }
```

In `readPrompt`, drop the `group:` read (location wins; `load()` stamps it):

```swift
        return Prompt(
            id: id,
            title: doc.fields["title"] ?? "Untitled",
            content: doc.body,
            group: nil,
            createdAt: created,
            updatedAt: updated
        )
```

- [ ] **Step 10: Run the whole suite (guard against regressions in existing flat tests)**

Run: `swift test`
Expected: PASS. If a pre-existing test asserted a `group:` frontmatter round-trip through `writePrompt`, update it to expect location-derived grouping (it now lives at root → `group == nil`).

- [ ] **Step 11: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository.swift Tests/PromptBoardKitTests/FolderStructureTests.swift
git commit -m "feat: recursive library scan derives folder from item location"
```

---

## Task F1: Folder CRUD primitives (create / rename / delete)

**Files:**
- Create: `Sources/PromptBoardKit/LibraryRepository+Folders.swift`
- Test: `Tests/PromptBoardKitTests/FolderStructureTests.swift` (append)

- [ ] **Step 1: Write failing tests for create + the folder-URL helper**

Append:

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/createFolder`
Expected: FAIL — `createFolder` is undefined.

- [ ] **Step 3: Create `LibraryRepository+Folders.swift` with the helpers + `createFolder`**

```swift
import Foundation

extension LibraryRepository {
    func treeRoot(for kind: LibraryEntry.Kind) -> URL {
        kind == .prompt ? promptsDirectoryURL : skillsDirectoryURL
    }

    // Validates a `/`-separated relative folder path (no empty/./.. components, not
    // absolute) and returns its absolute URL under the tree root. nil path == root.
    func folderURL(for kind: LibraryEntry.Kind, path: String?) throws -> URL {
        let root = treeRoot(for: kind)
        guard let path, !path.isEmpty else { return root }
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"),
              !components.contains(""),
              !components.contains("."),
              !components.contains("..")
        else {
            throw LibraryRepositoryError.invalidSkillSource(path: path)
        }
        return root.appendingPathComponent(path, isDirectory: true)
    }

    public func createFolder(kind: LibraryEntry.Kind, path: String) throws {
        try withExclusiveLock {
            let url = try folderURL(for: kind, path: path)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: path)
            }
            try ensureDirectory(url)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FolderStructureTests/createFolder`
Expected: PASS.

- [ ] **Step 5: Write failing tests for rename (moves descendants + is caught by reconcile)**

```swift
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
```

- [ ] **Step 6: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/renameFolderMovesEveryDescendant`
Expected: FAIL — `renameFolder` undefined.

- [ ] **Step 7: Add `renameFolder` (with skill-symlink repoint) and `deleteFolder`**

Append to `LibraryRepository+Folders.swift`:

```swift
    public func renameFolder(kind: LibraryEntry.Kind, from: String, to: String) throws {
        try withExclusiveLock {
            let oldURL = try folderURL(for: kind, path: from)
            let newURL = try folderURL(for: kind, path: to)
            guard FileManager.default.fileExists(atPath: oldURL.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: from)
            }
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: to)
            }
            // Record old skill-source paths (for symlink repoint) before the move.
            let movingSkills = kind == .skill ? skillFolderURLs().filter {
                $0.standardizedFileURL.path.hasPrefix(oldURL.standardizedFileURL.path + "/")
                    || $0.standardizedFileURL.path == oldURL.standardizedFileURL.path
            } : []
            try ensureDirectory(newURL.deletingLastPathComponent())
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            for oldSkillURL in movingSkills {
                let name = oldSkillURL.lastPathComponent
                let relative = String(oldSkillURL.standardizedFileURL.path
                    .dropFirst(oldURL.standardizedFileURL.path.count))
                let newSkillURL = URL(fileURLWithPath: newURL.standardizedFileURL.path + relative)
                SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: oldSkillURL)
                linkSkill(at: newSkillURL, name: name)
            }
        }
    }

    public func deleteFolder(kind: LibraryEntry.Kind, path: String) throws {
        try withExclusiveLock {
            let url = try folderURL(for: kind, path: path)
            guard url != treeRoot(for: kind),
                  FileManager.default.fileExists(atPath: url.path) else {
                throw LibraryRepositoryError.invalidSkillSource(path: path)
            }
            let parent = url.deletingLastPathComponent()
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil
            )) ?? []
            for child in children {
                // Record skill sources under this child before moving it up.
                let movingSkills = kind == .skill ? skillFolderURLs().filter {
                    let p = $0.standardizedFileURL.path
                    return p == child.standardizedFileURL.path
                        || p.hasPrefix(child.standardizedFileURL.path + "/")
                } : []
                let destination = uniqueDestination(for: child.lastPathComponent, in: parent)
                try FileManager.default.moveItem(at: child, to: destination)
                for oldSkillURL in movingSkills {
                    let name = oldSkillURL.lastPathComponent
                    let relative = String(oldSkillURL.standardizedFileURL.path
                        .dropFirst(child.standardizedFileURL.path.count))
                    let newSkillURL = URL(fileURLWithPath: destination.standardizedFileURL.path + relative)
                    SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: oldSkillURL)
                    linkSkill(at: newSkillURL, name: name)
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // Appends a numeric suffix if a same-named entry already exists in `directory`.
    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffixed = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(suffixed)
            counter += 1
        }
        return candidate
    }
```

- [ ] **Step 8: Write failing test for delete-moves-contents-up**

```swift
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
```

- [ ] **Step 9: Run the folder-CRUD tests**

Run: `swift test --filter FolderStructureTests`
Expected: PASS (create, escape-reject, rename, delete-moves-up all green).

- [ ] **Step 10: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+Folders.swift Tests/PromptBoardKitTests/FolderStructureTests.swift
git commit -m "feat: folder create/rename/delete primitives with skill relink"
```

---

## Task F2: Move primitives + recursive reconcile (sync survives nesting)

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository+Folders.swift` (append moves)
- Modify: `Sources/PromptBoardKit/LibraryRepository+Sync.swift` (recursive skill enumeration, ~22-33)
- Modify: `Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift` (`touchAndReadSkill` no longer resurrects `group`, ~182-194)
- Test: `Tests/PromptBoardKitTests/FolderStructureTests.swift` (append)

- [ ] **Step 1: Write failing test — a moved skill's symlink follows it**

```swift
    @Test func moveSkillRelinksItsSymlinkToTheNewLocation() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        try repo.moveSkill(id: skill.id, toFolder: "Work")

        let movedSource = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export").standardizedFileURL.path
        for dir in repo.syncTargets.all {
            let link = dir.appendingPathComponent("logo-export")
            #expect(SymlinkManager.resolvedDestination(of: link)?.path == movedSource)
        }
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/moveSkillRelinksItsSymlinkToTheNewLocation`
Expected: FAIL — `moveSkill` undefined.

- [ ] **Step 3: Add `movePrompt` + `moveSkill`**

Append to `LibraryRepository+Folders.swift`:

```swift
    public func movePrompt(id: UUID, toFolder folder: String?) throws {
        try withExclusiveLock {
            guard let found = try findPromptFile(id: id) else {
                throw LibraryRepositoryError.promptNotFound(id)
            }
            let destDir = try folderURL(for: .prompt, path: folder)
            try ensureDirectory(destDir)
            let destination = uniqueDestination(for: found.url.lastPathComponent, in: destDir)
            do {
                try FileManager.default.moveItem(at: found.url, to: destination)
            } catch {
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
        }
    }

    public func moveSkill(id: UUID, toFolder folder: String?) throws {
        try withExclusiveLock {
            guard let found = try findSkillFolder(id: id) else {
                throw LibraryRepositoryError.skillNotFound(id)
            }
            let name = found.url.lastPathComponent
            let destDir = try folderURL(for: .skill, path: folder)
            try ensureDirectory(destDir)
            let destination = destDir.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw LibraryRepositoryError.skillLinkConflict(name: name, path: destination.path)
            }
            SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: found.url)
            do {
                try FileManager.default.moveItem(at: found.url, to: destination)
            } catch {
                linkSkill(at: found.url, name: name)
                throw LibraryRepositoryError.ioFailure(underlying: error)
            }
            linkSkill(at: destination, name: name)
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FolderStructureTests/moveSkillRelinksItsSymlinkToTheNewLocation`
Expected: PASS.

- [ ] **Step 5: Write failing test — reconcile keeps a nested skill linked (does NOT prune it)**

```swift
    @Test func reconcileKeepsNestedSkillsLinkedInsteadOfPruningThem() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        try repo.moveSkill(id: skill.id, toFolder: "Work")

        _ = try repo.reconcileSync()

        let source = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export").standardizedFileURL.path
        for dir in repo.syncTargets.all {
            let link = dir.appendingPathComponent("logo-export")
            #expect(SymlinkManager.resolvedDestination(of: link)?.path == source)
        }
    }
```

- [ ] **Step 6: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/reconcileKeepsNestedSkillsLinkedInsteadOfPruningThem`
Expected: FAIL — `reconcileSync`'s flat `contentsOfDirectory` misses `Work/logo-export`, so `pruneStaleLinks` removes the link (resolves to nil).

- [ ] **Step 7: Make `reconcileSync` enumerate skills recursively**

In `LibraryRepository+Sync.swift`, replace the skill-folder enumeration block (the `let skillFolders = ...` through the `for folder in skillFolders` loop) with a reuse of the recursive walk:

```swift
        // Folder names are the on-disk truth. `Skill.name` comes from SKILL.md and
        // can differ from its folder (collision suffixes, hand edits), so enumerate.
        // Recursive: a skill may live at any depth; its symlink name is the leaf name.
        var skillNames = Set<String>()
        var sources: [String: URL] = [:]
        for folder in skillFolderURLs() {
            let name = folder.lastPathComponent
            skillNames.insert(name)
            sources[name] = folder
        }
```

(`skillFolderURLs()` already skips dot-entries and requires SKILL.md, so the prior inline guards are subsumed.)

- [ ] **Step 8: Run to verify it passes + guard mutation**

Run: `swift test --filter FolderStructureTests/reconcileKeepsNestedSkillsLinkedInsteadOfPruningThem`
Expected: PASS.

**Mutation check (required):** temporarily revert `skillFolderURLs()` in step 7 back to a flat `contentsOfDirectory` and re-run — the test MUST fail (proves it guards the recursion, not a tautology). Restore afterward.

- [ ] **Step 9: Stop the skill sidecar from resurrecting `group`**

In `LibraryRepository+SkillAuthoring.swift`, `touchAndReadSkill` currently writes `group: existing?.group ?? skill.group`. Since group is now location-derived and no longer stored, write `nil`:

```swift
    func touchAndReadSkill(id: UUID, in folderURL: URL, skill: Skill) throws -> Skill {
        let existing = readSidecar(in: folderURL)
        try writeSidecar(SkillSidecar(
            id: skill.id,
            group: nil,
            createdAt: existing?.createdAt ?? skill.createdAt,
            updatedAt: Date()
        ), in: folderURL)
        guard let refreshed = readSkill(at: folderURL) else {
            throw LibraryRepositoryError.skillNotFound(id)
        }
        return refreshed
    }
```

Do the same in `createSkill`/`promotePromptToSkill`/`updateSkill`/`updateSkillGroup` sidecar writes (pass `group: nil`), and in `readSkill` set `group: nil` (location wins; `load()` stamps it). Leave `SkillSidecar.group` in the struct for backward-compatible decoding of old sidecars.

- [ ] **Step 10: Run the full suite**

Run: `swift test`
Expected: PASS. Update any existing skill test that asserted a sidecar `group` round-trip to expect location-derived grouping.

- [ ] **Step 11: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+Folders.swift Sources/PromptBoardKit/LibraryRepository+Sync.swift Sources/PromptBoardKit/LibraryRepository+SkillAuthoring.swift Tests/PromptBoardKitTests/FolderStructureTests.swift
git commit -m "feat: move prompts/skills between folders; reconcile walks nested skills"
```

---

## Task F3: `addPrompt` honors a folder path; CLI files into subfolders

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository.swift` (`addPrompt` ~72-82)
- Test: `Tests/PromptBoardKitTests/FolderStructureTests.swift` (append)

- [ ] **Step 1: Write the failing test**

```swift
    @Test func addPromptWithAGroupPathCreatesItInThatSubfolder() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Deploy", content: "b", group: "Work/Ops")

        let expected = repo.promptsDirectoryURL.appendingPathComponent("Work/Ops/deploy.md").path
        #expect(FileManager.default.fileExists(atPath: expected))
        let loaded = try repo.load().items.first
        #expect(loaded?.group == "Work/Ops")
        #expect(loaded?.id == prompt.id)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/addPromptWithAGroupPathCreatesItInThatSubfolder`
Expected: FAIL — `addPrompt` writes to `prompts/deploy.md` at root, so the nested path does not exist.

- [ ] **Step 3: Update `addPrompt` to place the file in the folder given by `group`**

```swift
    @discardableResult
    public func addPrompt(title: String, content: String, group: String? = nil) throws -> Prompt {
        try withExclusiveLock {
            let destDir = try folderURL(for: .prompt, path: group)
            try ensureDirectory(destDir)
            let normalized = Self.normalizedTitle(title)
            let slug = Slug.unique(Slug.make(from: normalized), existing: existingPromptSlugs())
            let prompt = Prompt(title: normalized, content: content, group: nil)
            try writePrompt(prompt, to: destDir.appendingPathComponent("\(slug).md"))
            return prompt
        }
    }
```

(The stored `Prompt.group` is `nil`; the returned value's folder is authoritative only after a `load()`, which stamps it. Uniqueness stays global via `existingPromptSlugs()`.)

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FolderStructureTests/addPromptWithAGroupPathCreatesItInThatSubfolder`
Expected: PASS.

- [ ] **Step 5: Run the full suite (CLI uses `addPrompt(group:)`; nothing else changes)**

Run: `swift test`
Expected: PASS. The CLI `add --group X` and MCP `add_prompt(group:)` now file into `prompts/X/` unchanged in signature.

- [ ] **Step 6: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository.swift Tests/PromptBoardKitTests/FolderStructureTests.swift
git commit -m "feat: addPrompt files into the folder named by its group path"
```

---

## Task F4: One-time migration (flat group label → folder)

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryRepository+Folders.swift` (append migration)
- Modify: `Sources/PromptBoardKit/LibraryStore.swift` (`loadInitial()` ~226-234)
- Test: `Tests/PromptBoardKitTests/FolderStructureTests.swift` (append)

- [ ] **Step 1: Write the failing test**

```swift
    @Test func migrationMovesFlatGroupedItemsIntoFoldersAndLeavesUngroupedAtRoot() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        // A legacy grouped prompt (group in frontmatter, file at root).
        try "---\nid: \(UUID().uuidString)\ntitle: Grouped\ngroup: Work\n---\nb"
            .write(to: repo.promptsDirectoryURL.appendingPathComponent("grouped.md"), atomically: true, encoding: .utf8)
        // An ungrouped prompt stays put.
        try "---\nid: \(UUID().uuidString)\ntitle: Loose\n---\nb"
            .write(to: repo.promptsDirectoryURL.appendingPathComponent("loose.md"), atomically: true, encoding: .utf8)

        let didRun = try repo.migrateGroupsToFoldersIfNeeded()

        #expect(didRun)
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("Work/grouped.md").path))
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("loose.md").path))
        // Idempotent: a second run is a no-op.
        #expect(try repo.migrateGroupsToFoldersIfNeeded() == false)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter FolderStructureTests/migrationMovesFlatGroupedItemsIntoFoldersAndLeavesUngroupedAtRoot`
Expected: FAIL — `migrateGroupsToFoldersIfNeeded` undefined.

- [ ] **Step 3: Add the migration**

Append to `LibraryRepository+Folders.swift`:

```swift
    private var folderMigrationMarkerURL: URL {
        libraryURL.appendingPathComponent(".promptboard-folders-v1")
    }

    // One-time: move each item whose legacy frontmatter/sidecar `group` is set into a
    // top-level folder of that name. Idempotent via a marker file. Reads the group
    // directly (readPrompt/readSkill now ignore it) so it can act before the marker.
    @discardableResult
    public func migrateGroupsToFoldersIfNeeded() throws -> Bool {
        guard !FileManager.default.fileExists(atPath: folderMigrationMarkerURL.path) else { return false }
        return try withExclusiveLock {
            guard !FileManager.default.fileExists(atPath: folderMigrationMarkerURL.path) else { return false }

            for url in promptFileURLs() {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                guard let group = Frontmatter.parse(text).fields["group"], !group.isEmpty else { continue }
                guard Self.folderPath(of: url, underRoot: promptsDirectoryURL) == nil else { continue }
                let destDir = try folderURL(for: .prompt, path: group)
                try ensureDirectory(destDir)
                let destination = uniqueDestination(for: url.lastPathComponent, in: destDir)
                try? FileManager.default.moveItem(at: url, to: destination)
            }
            for folderURL in skillFolderURLs() {
                guard let group = readSidecar(in: folderURL)?.group, !group.isEmpty else { continue }
                guard Self.folderPath(of: folderURL, underRoot: skillsDirectoryURL) == nil else { continue }
                let name = folderURL.lastPathComponent
                let destDir = try self.folderURL(for: .skill, path: group)
                try ensureDirectory(destDir)
                let destination = destDir.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
                SymlinkManager.unlink(name: name, from: syncTargets.all, expectedTarget: folderURL)
                try? FileManager.default.moveItem(at: folderURL, to: destination)
                linkSkill(at: destination, name: name)
            }

            try Data("v1".utf8).write(to: folderMigrationMarkerURL, options: .atomic)
            return true
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter FolderStructureTests/migrationMovesFlatGroupedItemsIntoFoldersAndLeavesUngroupedAtRoot`
Expected: PASS.

- [ ] **Step 5: Wire migration into `LibraryStore.loadInitial()`**

In `LibraryStore.swift`, call it after the legacy migration, before the first refresh:

```swift
    private func loadInitial() {
        let freshInstall = !FileManager.default.fileExists(atPath: repository.libraryURL.path)
        let migrated = (try? repository.migrateLegacyIfNeeded()) ?? false
        if freshInstall, !migrated {
            _ = try? repository.seedPromptsIfEmpty(SeedPrompts.samples)
        }
        _ = try? repository.migrateGroupsToFoldersIfNeeded()
        refreshFromDisk()
        refreshExternalItems()
    }
```

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/PromptBoardKit/LibraryRepository+Folders.swift Sources/PromptBoardKit/LibraryStore.swift Tests/PromptBoardKitTests/FolderStructureTests.swift
git commit -m "feat: one-time migration from flat group labels to folders"
```

---

## Task F5: Store wrappers + AppState folder tree & filtering

**Files:**
- Modify: `Sources/PromptBoardKit/LibraryStore.swift` (append wrappers)
- Create: `Sources/PromptBoardApp/Overlay/FolderTree.swift`
- Modify: `Sources/PromptBoardApp/AppState.swift` (`selectedGroup`→`selectedFolder`, `visibleItems` ~60-67, `groupCounts`→`folderTree` ~75-81)
- Test: `Tests/PromptBoardKitTests/FolderStructureTests.swift` (FolderNode build test)

- [ ] **Step 1: Add non-throwing `LibraryStore` wrappers**

Append to `LibraryStore.swift` (after the skill-authoring section):

```swift
    // MARK: - Folders

    @discardableResult
    public func createFolder(kind: LibraryEntry.Kind, path: String) -> Bool {
        do { try repository.createFolder(kind: kind, path: path); refreshFromDisk(); return true }
        catch { reportFailure(error); return false }
    }

    @discardableResult
    public func renameFolder(kind: LibraryEntry.Kind, from: String, to: String) -> Bool {
        do { try repository.renameFolder(kind: kind, from: from, to: to); refreshFromDisk(); return true }
        catch { reportFailure(error); return false }
    }

    @discardableResult
    public func deleteFolder(kind: LibraryEntry.Kind, path: String) -> Bool {
        do { try repository.deleteFolder(kind: kind, path: path); refreshFromDisk(); return true }
        catch { reportFailure(error); return false }
    }

    // Routes by id: move a prompt if one matches, else a skill.
    @discardableResult
    public func moveItem(id: UUID, toFolder folder: String?) -> Bool {
        do { try repository.movePrompt(id: id, toFolder: folder); refreshFromDisk(); return true }
        catch LibraryRepositoryError.promptNotFound {
        } catch { reportFailure(error); return false }
        do { try repository.moveSkill(id: id, toFolder: folder); refreshFromDisk(); return true }
        catch { reportFailure(error); return false }
        return false
    }
```

- [ ] **Step 2: Write the FolderNode build test**

Append to `FolderStructureTests.swift`:

```swift
    @Test func folderNodesNestByPathWithSubtreeCounts() {
        let items: [LibraryEntry] = [
            .prompt(Prompt(title: "a", content: "", group: "Work")),
            .prompt(Prompt(title: "b", content: "", group: "Work/ClientA")),
            .prompt(Prompt(title: "c", content: "", group: nil)),
        ]
        let roots = FolderNode.build(from: items)
        let work = roots.first { $0.name == "Work" }
        #expect(work != nil)
        #expect(work?.path == "Work")
        #expect(work?.subtreeCount == 2)               // its own + ClientA's
        #expect(work?.children.first?.name == "ClientA")
        #expect(work?.children.first?.path == "Work/ClientA")
    }
```

(`FolderNode` lives in the App target, so this test must move to an App-target test bundle **or** `FolderNode` must live in Kit. To keep the App dependency-light and this test runnable, place `FolderNode` in **PromptBoardKit** as `Sources/PromptBoardKit/FolderTree.swift` and import it in the App. Adjust the Create path below accordingly.)

- [ ] **Step 3: Create `FolderNode` in Kit**

Create `Sources/PromptBoardKit/FolderTree.swift`:

```swift
import Foundation

// A node in the sidebar folder tree, built purely from items' derived `group` paths.
public struct FolderNode: Identifiable, Equatable, Sendable {
    public let name: String          // last path component, e.g. "ClientA"
    public let path: String          // full relative path, e.g. "Work/ClientA"
    public var children: [FolderNode]
    public var directCount: Int      // items whose group == this path
    public var subtreeCount: Int     // directCount + all descendants

    public var id: String { path }

    public static func build(from items: [LibraryEntry]) -> [FolderNode] {
        // Collect every folder path that appears, plus every ancestor.
        var directCounts: [String: Int] = [:]
        var allPaths = Set<String>()
        for item in items {
            guard let group = item.group, !group.isEmpty else { continue }
            directCounts[group, default: 0] += 1
            var parts = group.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                allPaths.insert(parts.joined(separator: "/"))
                parts.removeLast()
            }
        }
        func node(for path: String) -> FolderNode {
            let childPaths = allPaths.filter { candidate in
                candidate.hasPrefix(path + "/")
                    && !candidate.dropFirst(path.count + 1).contains("/")
            }
            let children = childPaths.sorted().map(node(for:))
            let direct = directCounts[path] ?? 0
            return FolderNode(
                name: String(path.split(separator: "/").last ?? ""),
                path: path,
                children: children,
                directCount: direct,
                subtreeCount: direct + children.reduce(0) { $0 + $1.subtreeCount }
            )
        }
        let topLevel = allPaths.filter { !$0.contains("/") }.sorted()
        return topLevel.map(node(for:))
    }
}
```

- [ ] **Step 4: Run the FolderNode test**

Run: `swift test --filter FolderStructureTests/folderNodesNestByPathWithSubtreeCounts`
Expected: PASS.

- [ ] **Step 5: Rewire AppState to folders**

In `AppState.swift`: rename the property and update the filter + tree:

```swift
    var selectedFolder: String?
```

```swift
    var visibleItems: [LibraryEntry] {
        var items = store.items
        if let selectedFolder {
            // Finder-style: the folder itself plus everything nested under it.
            items = items.filter {
                $0.group == selectedFolder || ($0.group?.hasPrefix(selectedFolder + "/") ?? false)
            }
        }
        return PromptFilter.filter(items, query: searchText)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var folderTree: [FolderNode] {
        FolderNode.build(from: store.items)
    }
```

Add folder actions near the other mutators:

```swift
    func createFolder(named name: String, under parent: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = parent.map { "\($0)/\(trimmed)" } ?? trimmed
        // Prompts and skills share the folder namespace in the sidebar; create in both
        // trees so an empty folder shows regardless of what gets dropped into it.
        _ = store.createFolder(kind: .prompt, path: path)
        _ = store.createFolder(kind: .skill, path: path)
    }

    func moveItem(id: UUID, toFolder folder: String?) {
        _ = store.moveItem(id: id, toFolder: folder)
    }
```

Replace any remaining `selectedGroup` references (e.g. `resetTransientState`, sidebar) with `selectedFolder`.

- [ ] **Step 6: Build the app target**

Run: `swift build`
Expected: Build complete. Fix any leftover `selectedGroup`/`groupCounts` references the compiler flags.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: PASS (147 prior + new folder tests).

- [ ] **Step 8: Commit**

```bash
git add Sources/PromptBoardKit/LibraryStore.swift Sources/PromptBoardKit/FolderTree.swift Sources/PromptBoardApp/AppState.swift Tests/PromptBoardKitTests/FolderStructureTests.swift
git commit -m "feat: folder store wrappers, FolderNode tree, folder-aware AppState"
```

---

## Task F6: Sidebar tree UI + drag-and-drop move

**Files:**
- Modify: `Sources/PromptBoardApp/Overlay/GroupSidebarView.swift` (full rewrite to recursive tree)
- Modify: `Sources/PromptBoardApp/Overlay/PromptCardView.swift` (add `.draggable`)
- Modify: `Sources/PromptBoardApp/DebugHooks.swift` (folder-op hooks)
- Verification: harness (App views have no unit tests — the pattern set by Layers B–E)

- [ ] **Step 1: Add drag to prompt/skill cards**

In `PromptCardView.swift`, add after the existing `.gesture(...)` chain on the card body (`item.id` is a `UUID`; carry it as a plain string):

```swift
        .draggable(item.id.uuidString)
```

- [ ] **Step 2: Rewrite `GroupSidebarView` as a recursive tree with drop targets**

Replace the body of `GroupSidebarView.swift`:

```swift
import SwiftUI
import PromptBoardKit

struct GroupSidebarView: View {
    @Bindable var appState: AppState
    @State private var expanded: Set<String> = []
    @State private var creatingUnder: String? = nil
    @State private var newFolderName = ""
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("GROUPS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.bottom, 6)

            allRow
            ForEach(appState.folderTree) { node in
                folderRows(node, depth: 0)
            }

            newFolderField

            Spacer(minLength: 0)

            Toggle("Show external", isOn: $appState.showExternalItems)
                .toggleStyle(.switch).controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.horizontal, 11).padding(.bottom, 12)
        }
        .padding(.top, 64).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
    }

    private var allRow: some View {
        rowButton(
            title: "All", systemImage: "square.stack.3d.up.fill",
            folder: nil, count: appState.store.items.count, depth: 0, hasChildren: false
        )
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init) { appState.moveItem(id: id, toFolder: nil) }
            return true
        }
    }

    @ViewBuilder
    private func folderRows(_ node: FolderNode, depth: Int) -> some View {
        rowButton(
            title: node.name, systemImage: "folder.fill",
            folder: node.path, count: node.subtreeCount, depth: depth,
            hasChildren: !node.children.isEmpty
        )
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init) { appState.moveItem(id: id, toFolder: node.path) }
            return true
        }
        if expanded.contains(node.path) {
            ForEach(node.children) { child in
                folderRows(child, depth: depth + 1)
            }
        }
    }

    private func rowButton(
        title: String, systemImage: String, folder: String?, count: Int, depth: Int, hasChildren: Bool
    ) -> some View {
        let selected = appState.selectedFolder == folder
        return Button {
            appState.selectedFolder = folder
        } label: {
            HStack(spacing: 6) {
                if hasChildren {
                    Button {
                        if expanded.contains(folder ?? "") { expanded.remove(folder ?? "") }
                        else { expanded.insert(folder ?? "") }
                    } label: {
                        Image(systemName: expanded.contains(folder ?? "") ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9)).frame(width: 10)
                    }.buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: systemImage).font(.system(size: 11)).frame(width: 16)
                Text(title).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10.5))
                    .foregroundStyle(selected ? accent.opacity(0.9) : .white.opacity(0.4))
            }
            .padding(.leading, CGFloat(depth) * 12)
            .foregroundStyle(selected ? .white : .white.opacity(0.66))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var newFolderField: some View {
        if creatingUnder != nil || newFolderName.isEmpty == false {
            HStack {
                TextField("New folder", text: $newFolderName)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit {
                        appState.createFolder(named: newFolderName, under: appState.selectedFolder)
                        newFolderName = ""; creatingUnder = nil
                    }
            }.padding(.horizontal, 11).padding(.top, 4)
        } else {
            Button {
                creatingUnder = appState.selectedFolder
            } label: {
                Label("New folder", systemImage: "folder.badge.plus")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }.buttonStyle(.plain).padding(.horizontal, 11).padding(.top, 4)
        }
    }
}
```

- [ ] **Step 3: Add debug hooks for harness verification**

In `DebugHooks.swift`, add notification names + handlers mirroring the existing pattern (e.g. `createFolderNotification` → `appState.createFolder(named: object, under: nil)`, `moveFirstItemNotification` → move the first visible item into the object-named folder, `dumpFolderTreeNotification` → NSLog the tree). Follow the exact registration shape used by `handleCreateSampleSkill`.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Harness-verify the tree + a real drag-move**

```bash
SCRATCH=<scratchpad>/f6-verify
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"/{data,claude,agents,ext}
PROMPTBOARD_DEBUG=1 PROMPTBOARD_SHOW_ON_LAUNCH=1 \
  PROMPTBOARD_DATA_DIR="$SCRATCH/data" \
  PROMPTBOARD_CLAUDE_SKILLS_DIR="$SCRATCH/claude" \
  PROMPTBOARD_AGENTS_SKILLS_DIR="$SCRATCH/agents" \
  PROMPTBOARD_EXTERNAL_SCAN_ROOTS="$SCRATCH/ext" \
  .build/debug/PromptBoardApp > "$SCRATCH/app.log" 2>&1 &
echo $! > "$SCRATCH/pid"; sleep 3
# create a folder, move the first prompt into it, dump the tree + snapshot
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.arya.PromptBoard.debug.createFolder"), object: "Work", userInfo: nil, deliverImmediately: true)'
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.arya.PromptBoard.debug.moveFirstItem"), object: "Work", userInfo: nil, deliverImmediately: true)'
sleep 1
xcrun swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("com.arya.PromptBoard.debug.snapshot"), object: "'"$SCRATCH"'/tree.png", userInfo: nil, deliverImmediately: true)'
sleep 2
ls -la "$SCRATCH/data/Library/prompts/Work"     # the moved file is here on disk
```

Expected: the moved prompt's `.md` file exists under `Library/prompts/Work/`; the snapshot shows a `Work` folder row with count 1; `app.log` shows no repository-failure lines. Then `kill $(cat "$SCRATCH/pid"); rm -rf "$SCRATCH"`.

- [ ] **Step 6: Commit**

```bash
git add Sources/PromptBoardApp/Overlay/GroupSidebarView.swift Sources/PromptBoardApp/Overlay/PromptCardView.swift Sources/PromptBoardApp/DebugHooks.swift
git commit -m "feat: folder tree sidebar with expand/collapse and drag-to-move"
```

---

## Task F7: Smoke, docs, memory

**Files:**
- Modify: `README.md`, `docs/design/2026-08-08-folder-structure-design.md` (status), memory `promptboard-app.md`

- [ ] **Step 1: Full build + test + app bundle**

Run: `swift build && swift test && make app`
Expected: build complete, all tests pass, `dist/PromptBoard.app` signed with the stable identity.

- [ ] **Step 2: Real smoke in the installed app**

Reinstall (`pkill -x PromptBoard; rm -rf ~/Applications/PromptBoard.app; cp -R dist/PromptBoard.app ~/Applications/; open ~/Applications/PromptBoard.app`). Then, by hand: create a folder, drag a prompt into it (confirm the file moved in `~/Library/Application Support/PromptBoard/Library/prompts/<Folder>/`), drag a **skill** into a folder and confirm `claude` / the tool dirs still resolve its symlink (`ls -laL ~/.claude/skills/<slug>`), and confirm existing groups migrated to top-level folders on first launch.

- [ ] **Step 3: Update README + design status + memory**

Add a "Folders" section to `README.md` (nested folders, drag-to-move, migration note, sync unaffected). Mark the design doc `Status: implemented`. Append a Layer F paragraph to `promptboard-app.md` memory (recursive scan + reconcile, group repurposed as location-derived path, migration marker `.promptboard-folders-v1`, drag-drop-only move).

- [ ] **Step 4: Commit + push + merge**

```bash
git add README.md docs/ && git commit -m "docs: document nested folders (Layer F)"
git checkout main && git merge --no-ff <feature-branch> -m "Merge: nested folders (Layer F)"
git push origin main
```

---

## Self-review

- **Spec coverage:** real nested dirs replacing `group` (F0, decisions 1–2) ✓; migration incl. no-group case (F4) ✓; tree sidebar with subtree-inclusive selection (F5/F6) ✓; drag-and-drop move incl. All-root drop (F6) ✓; delete-moves-contents-up (F1) ✓; per-folder-not-global slug uniqueness backed by SyncConflict (F0/F2, decision 5) ✓; cross-tool sync unaffected in contract, recursive in enumeration (F2, decision 3) ✓.
- **Placeholder scan:** none — every code step is real Swift; the only "follow the existing pattern" is the DebugHooks registration (F6 step 3), which is mechanical mirroring of `handleCreateSampleSkill` and acceptable for a harness-only hook.
- **Type consistency:** `folderURL(for:path:)`, `folderPath(of:underRoot:)`, `treeRoot(for:)`, `createFolder/renameFolder/deleteFolder/movePrompt/moveSkill`, `FolderNode.build(from:)`, `AppState.selectedFolder/folderTree/createFolder(named:under:)/moveItem(id:toFolder:)`, `LibraryStore.createFolder/renameFolder/deleteFolder/moveItem` — names used identically across tasks.
- **Kind type:** every primitive uses `LibraryEntry.Kind` (`.prompt`/`.skill`), the existing public enum — no new discriminator introduced.
