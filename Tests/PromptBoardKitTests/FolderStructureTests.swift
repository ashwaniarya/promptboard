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

    @Test func deleteFolderRefusesToDeleteTheTreeRoot() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        #expect(throws: LibraryRepositoryError.self) {
            try repo.deleteFolder(kind: .prompt, path: "")
        }
    }

    @Test func deleteFolderSuffixesAChildThatCollidesWithAnExistingSibling() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        // A "Notes" folder already exists at the prompts root.
        let existing = repo.promptsDirectoryURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        // A doomed folder that also contains a "Notes" child.
        let doomed = repo.promptsDirectoryURL.appendingPathComponent("Doomed", isDirectory: true)
        let collidingChild = doomed.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: collidingChild, withIntermediateDirectories: true)
        try "x".write(to: collidingChild.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        try repo.deleteFolder(kind: .prompt, path: "Doomed")

        // The original Notes survives, and the colliding child lands as Notes-2.
        #expect(FileManager.default.fileExists(atPath: existing.path))
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("Notes-2/marker.txt").path))
        #expect(!FileManager.default.fileExists(atPath: doomed.path))
    }

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

    @Test func movePromptRelocatesItsFileAndItsFolderReadsBackFromLocation() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Deploy Notes", content: "b")
        try repo.movePrompt(id: prompt.id, toFolder: "Work/Ops")

        let moved = repo.promptsDirectoryURL.appendingPathComponent("Work/Ops/deploy-notes.md").path
        #expect(FileManager.default.fileExists(atPath: moved))
        let reloaded = try repo.load().items.first { $0.id == prompt.id }
        #expect(reloaded?.group == "Work/Ops")
    }

    @Test func moveSkillMakesItsGroupReadBackAsTheNewFolder() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        try repo.moveSkill(id: skill.id, toFolder: "Work")

        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "Work")
    }

    @Test func moveSkillRefusesWhenAnEntryAlreadyOccupiesTheDestination() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        // Pre-create a colliding entry at skills/Work/logo-export.
        let clash = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export", isDirectory: true)
        try FileManager.default.createDirectory(at: clash, withIntermediateDirectories: true)
        #expect(throws: LibraryRepositoryError.self) {
            try repo.moveSkill(id: skill.id, toFolder: "Work")
        }
    }

    @Test func addPromptWithAGroupPathCreatesItInThatSubfolder() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Deploy", content: "b", group: "Work/Ops")

        let expected = repo.promptsDirectoryURL.appendingPathComponent("Work/Ops/deploy.md").path
        #expect(FileManager.default.fileExists(atPath: expected))
        let loaded = try repo.load().items.first
        #expect(loaded?.group == "Work/Ops")
        #expect(loaded?.id == prompt.id)
        // The returned value echoes the folder it was filed into (for CLI/MCP responses).
        #expect(prompt.group == "Work/Ops")
    }

    @Test func addPromptWithATraversalGroupThrowsAndWritesNothingOutsideTheTree() throws {
        let repo = tempLibrary()
        #expect(throws: LibraryRepositoryError.self) {
            try repo.addPrompt(title: "Escape", content: "b", group: "../escape")
        }
        // Nothing leaked outside the prompts tree.
        let escaped = repo.libraryURL.appendingPathComponent("escape.md").path
        #expect(!FileManager.default.fileExists(atPath: escaped))
    }

    @Test func movePromptToItsCurrentFolderIsANoOpNotADuplicate() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Deploy", content: "b", group: "Work")
        // Move it to the same folder it already lives in.
        try repo.movePrompt(id: prompt.id, toFolder: "Work")

        let items = try repo.load().items.filter { $0.id == prompt.id }
        #expect(items.count == 1)
        #expect(items.first?.group == "Work")
        // No stray suffixed duplicate file.
        #expect(!FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("Work/deploy-2.md").path))
    }

    @Test func moveSkillToItsCurrentFolderIsANoOpNotAConflict() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        try repo.moveSkill(id: skill.id, toFolder: "Work")
        // Second move to the SAME folder must not throw.
        try repo.moveSkill(id: skill.id, toFolder: "Work")

        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "Work")
        // Symlink still resolves to the skill in Work.
        let source = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export").standardizedFileURL.path
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("logo-export"))?.path == source)
        }
    }

    // MARK: - Authoring into a group folder (F8)

    @Test func createSkillFilesIntoTheGivenFolder() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: "Brand", body: "b")

        #expect(FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export/SKILL.md").path))
        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "Brand")
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("logo-export"))?.path
                    == repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export").standardizedFileURL.path)
        }
    }

    @Test func promotePromptToSkillFilesIntoTheGivenFolder() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Logo Export", content: "the body")
        let skill = try repo.promotePromptToSkill(
            promptID: prompt.id, name: "Logo Export", description: "d", group: "Brand", removingPrompt: true
        )

        #expect(FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export/SKILL.md").path))
        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "Brand")
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("logo-export"))?.path
                    == repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export").standardizedFileURL.path)
        }
    }

    @Test func importSkillFilesIntoTheGivenFolder() throws {
        let repo = tempLibrary()
        let source = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ImportSource-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "---\nname: logo-export\ndescription: d\n---\nbody"
            .write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let skill = try repo.importSkill(fromDirectory: source, group: "Brand")

        #expect(FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export/SKILL.md").path))
        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "Brand")
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("logo-export"))?.path
                    == repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export").standardizedFileURL.path)
        }
    }

    @Test func updateSkillMovesItIntoTheNewGroupFolderKeepingID() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: "A", body: "b")
        let updated = try repo.updateSkill(id: skill.id, name: "Logo Export", description: "d2", group: "B", body: "b2")

        #expect(updated.id == skill.id)
        #expect(FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("B/logo-export/SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("A/logo-export").path))
        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "B")
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("logo-export"))?.path
                    == repo.skillsDirectoryURL.appendingPathComponent("B/logo-export").standardizedFileURL.path)
        }
    }

    // The composition subtlety: renameSkillFolder always targets the skills ROOT, so a
    // renamed-in-subfolder skill momentarily lands at root before the group relocate pulls
    // it into the folder. Both ops fix the symlink; assert it never strands at root.
    @Test func updateSkillRenamesAndMovesInOneSaveKeepingID() throws {
        let repo = tempLibrary()
        let skill = try repo.createSkill(name: "Old Name", description: "d", group: "A", body: "b")
        let updated = try repo.updateSkill(id: skill.id, name: "New Name", description: "d", group: "B", body: "b")

        #expect(updated.id == skill.id)
        #expect(updated.name == "new-name")
        #expect(FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("B/new-name/SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("A/old-name").path))
        #expect(!FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("new-name").path))
        let reloaded = try repo.load().items.first { $0.id == skill.id }
        #expect(reloaded?.group == "B")
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("new-name"))?.path
                    == repo.skillsDirectoryURL.appendingPathComponent("B/new-name").standardizedFileURL.path)
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("old-name")) == nil)
        }
    }

    @Test func updatePromptWithAGroupMovesTheFileKeepingID() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Deploy Notes", content: "b")
        let updated = try repo.updatePrompt(id: prompt.id, title: nil, content: nil, group: "Work")

        #expect(updated.id == prompt.id)
        #expect(updated.group == "Work")
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("Work/deploy-notes.md").path))
        #expect(!FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("deploy-notes.md").path))
        let reloaded = try repo.load().items.first { $0.id == prompt.id }
        #expect(reloaded?.group == "Work")
    }

    @Test func updatePromptWithNilGroupRenamesButDoesNotMoveTheFile() throws {
        let repo = tempLibrary()
        let prompt = try repo.addPrompt(title: "Deploy Notes", content: "b", group: "Ops")
        let updated = try repo.updatePrompt(id: prompt.id, title: "New Title", content: nil, group: nil)

        #expect(updated.title == "New Title")
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("Ops/deploy-notes.md").path))
        let reloaded = try repo.load().items.first { $0.id == prompt.id }
        #expect(reloaded?.group == "Ops")
        #expect(reloaded?.title == "New Title")
    }

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
        // The marker file is written so the migration is recorded as done.
        #expect(FileManager.default.fileExists(atPath: repo.libraryURL.appendingPathComponent(".promptboard-folders-v1").path))
        // Idempotent: a second run is a no-op.
        #expect(try repo.migrateGroupsToFoldersIfNeeded() == false)
    }

    @Test func migrationLeavesAnAlreadyNestedItemAloneEvenWithAStaleSidecarGroup() throws {
        let repo = tempLibrary()
        // A skill already living in folder A, but whose sidecar still says group B.
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        try repo.moveSkill(id: skill.id, toFolder: "A")
        let nested = repo.skillsDirectoryURL.appendingPathComponent("A/logo-export", isDirectory: true)
        try "{\"id\":\"\(skill.id.uuidString)\",\"group\":\"B\",\"createdAt\":\"2020-01-01T00:00:00.000Z\",\"updatedAt\":\"2020-01-01T00:00:00.000Z\"}"
            .write(to: nested.appendingPathComponent(".promptboard.json"), atomically: true, encoding: .utf8)

        _ = try repo.migrateGroupsToFoldersIfNeeded()

        // The stale sidecar group must NOT drag it into B — location wins.
        #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: repo.skillsDirectoryURL.appendingPathComponent("B/logo-export").path))
    }

    @Test func migrationMovesAGroupedSkillIntoItsFolderAndRepointsTheSymlink() throws {
        let repo = tempLibrary()
        // Author a skill at root, then hand-write a legacy group into its sidecar.
        let skill = try repo.createSkill(name: "Logo Export", description: "d", group: nil, body: "b")
        let folder = repo.skillsDirectoryURL.appendingPathComponent("logo-export", isDirectory: true)
        try "{\"id\":\"\(skill.id.uuidString)\",\"group\":\"Brand\",\"createdAt\":\"2020-01-01T00:00:00.000Z\",\"updatedAt\":\"2020-01-01T00:00:00.000Z\"}"
            .write(to: folder.appendingPathComponent(".promptboard.json"), atomically: true, encoding: .utf8)

        _ = try repo.migrateGroupsToFoldersIfNeeded()

        let movedSource = repo.skillsDirectoryURL.appendingPathComponent("Brand/logo-export").standardizedFileURL.path
        #expect(FileManager.default.fileExists(atPath: movedSource + "/SKILL.md"))
        for dir in repo.syncTargets.all {
            #expect(SymlinkManager.resolvedDestination(of: dir.appendingPathComponent("logo-export"))?.path == movedSource)
        }
    }

    @Test func migrationSkipsAnItemWithAMalformedGroupAndStillCompletes() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        // A legacy prompt whose group label is not a valid folder path.
        try "---\nid: \(UUID().uuidString)\ntitle: Bad\ngroup: /misc\n---\nb"
            .write(to: repo.promptsDirectoryURL.appendingPathComponent("bad.md"), atomically: true, encoding: .utf8)
        // A well-formed grouped prompt that must still migrate.
        try "---\nid: \(UUID().uuidString)\ntitle: Good\ngroup: Work\n---\nb"
            .write(to: repo.promptsDirectoryURL.appendingPathComponent("good.md"), atomically: true, encoding: .utf8)

        let didRun = try repo.migrateGroupsToFoldersIfNeeded()

        #expect(didRun)
        // The bad item stays at the root, ungrouped.
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("bad.md").path))
        // The good item migrated into its folder.
        #expect(FileManager.default.fileExists(atPath: repo.promptsDirectoryURL.appendingPathComponent("Work/good.md").path))
        // Migration completed (marker written) — a second run is a no-op.
        #expect(try repo.migrateGroupsToFoldersIfNeeded() == false)
    }

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
        #expect(work?.subtreeCount == 2)
        #expect(work?.children.first?.name == "ClientA")
        #expect(work?.children.first?.path == "Work/ClientA")
    }

    @Test func folderNodesMaterializePureAncestorsWithZeroDirectCount() {
        // A single deep item: A and A/B are pure ancestors (no direct items), A/B/C holds it.
        let roots = FolderNode.build(from: [.prompt(Prompt(title: "x", content: "", group: "A/B/C"))])

        #expect(roots.count == 1)
        let a = roots.first
        #expect(a?.path == "A")
        #expect(a?.directCount == 0)
        #expect(a?.subtreeCount == 1)
        let b = a?.children.first
        #expect(b?.path == "A/B")
        #expect(b?.directCount == 0)
        #expect(b?.subtreeCount == 1)
        let c = b?.children.first
        #expect(c?.path == "A/B/C")
        #expect(c?.directCount == 1)
        #expect(c?.subtreeCount == 1)
    }

    @Test func folderNodesKeepSiblingsWithASharedPrefixSeparate() {
        // "A/B" must not swallow "A/BC" as a child — the slash boundary guards it.
        let roots = FolderNode.build(from: [
            .prompt(Prompt(title: "x", content: "", group: "A/B")),
            .prompt(Prompt(title: "y", content: "", group: "A/BC")),
        ])
        let a = roots.first { $0.path == "A" }
        #expect(a?.children.map(\.name).sorted() == ["B", "BC"])
        #expect(a?.subtreeCount == 2)
    }

    @Test func folderNodesIncludeEmptyOnDiskFoldersFromExtraPaths() {
        // An on-disk folder with no items still appears (directCount 0) so a freshly
        // created empty folder is visible in the sidebar.
        let roots = FolderNode.build(
            from: [.prompt(Prompt(title: "x", content: "", group: "Work"))],
            extraFolderPaths: ["Work/Empty", "Personal"]
        )
        let work = roots.first { $0.path == "Work" }
        #expect(work?.children.first?.path == "Work/Empty")
        #expect(work?.children.first?.directCount == 0)
        #expect(roots.contains { $0.path == "Personal" && $0.directCount == 0 })
    }

    @Test func folderPathsListsOrganizationalDirsAcrossBothTreesDedupedExcludingSkillLeaves() throws {
        let repo = tempLibrary()
        try repo.ensureLibraryDirectories()
        // prompts/Work/ and prompts/Personal/ are organizational folders.
        try FileManager.default.createDirectory(at: repo.promptsDirectoryURL.appendingPathComponent("Work/ClientA"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.promptsDirectoryURL.appendingPathComponent("Personal"), withIntermediateDirectories: true)
        // skills/Work/logo-export/ is a SKILL (has SKILL.md) — "Work" is a folder, the skill is not.
        let skill = repo.skillsDirectoryURL.appendingPathComponent("Work/logo-export")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: logo-export\ndescription: d\n---\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let paths = repo.folderPaths()

        #expect(paths == ["Personal", "Work", "Work/ClientA"])
    }
}
