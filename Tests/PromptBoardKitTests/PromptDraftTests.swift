import Foundation
import Testing
@testable import PromptBoardKit

struct PromptDraftTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardPromptDraftTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func draftPrefillsTrimmedTitleAndEmptyContent() {
        let draft = PromptDraft(title: "  zzqq \n")
        #expect(draft.title == "zzqq")
        #expect(draft.content.isEmpty)
        #expect(!draft.canSave)
    }

    @Test func canSaveNeedsTitleAndContent() {
        var draft = PromptDraft()
        draft.content = "body"
        #expect(!draft.canSave)
        draft.title = "Title"
        #expect(draft.canSave)
        draft.content = " \n "
        #expect(!draft.canSave)
    }

    @Test func chainDraftPrefillsTrimmedTitle() {
        let draft = ChainDraft(title: " zzqq ")
        #expect(draft.chainID == nil)
        #expect(draft.title == "zzqq")
        #expect(draft.steps.isEmpty)
    }

    @Test @MainActor func saveWritesAPromptToTheLibrary() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let seededCount = store.prompts.count
        var draft = PromptDraft(title: "zzqq")
        draft.content = "line one\nline two"

        let saved = try #require(store.savePrompt(draft))

        #expect(store.prompts.count == seededCount + 1)
        #expect(saved.title == "zzqq")
        #expect(saved.content == "line one\nline two")
        let reloaded = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        #expect(reloaded.prompts.first { $0.id == saved.id }?.content == "line one\nline two")
    }

    @Test @MainActor func unsavableDraftIsNotWritten() {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let seededCount = store.prompts.count
        #expect(store.savePrompt(PromptDraft(title: "zzqq")) == nil)
        #expect(store.prompts.count == seededCount)
    }
    @Test func editDraftPrefillsTheExistingPrompt() {
        let prompt = Prompt(title: "Old", content: "old body")
        let draft = PromptDraft(prompt: prompt)
        #expect(draft.promptID == prompt.id)
        #expect(draft.title == "Old")
        #expect(draft.content == "old body")
        #expect(PromptDraft(title: "x").promptID == nil)
    }

    @Test @MainActor func savingAnEditKeepsTheSamePromptAndFile() throws {
        let directory = temporaryDirectory()
        let store = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let original = store.add(title: "zzqq old", content: "old body")
        let promptsFolder = directory.appendingPathComponent("Library/prompts", isDirectory: true)
        let filesBefore = try FileManager.default.subpathsOfDirectory(atPath: promptsFolder.path).sorted()
        var draft = PromptDraft(prompt: original)
        draft.title = "zzqq new"
        draft.content = "new body"

        let saved = try #require(store.savePrompt(draft))

        #expect(saved.id == original.id)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: promptsFolder.path).sorted() == filesBefore)
        let reloaded = LibraryStore(directoryURL: directory, syncTargets: .temporary())
        let reloadedPrompt = try #require(reloaded.prompts.first { $0.id == original.id })
        #expect(reloadedPrompt.title == "zzqq new")
        #expect(reloadedPrompt.content == "new body")
        #expect(reloaded.prompts.filter { $0.title.hasPrefix("zzqq") }.count == 1)
    }

    @Test @MainActor func savingAnEditOfADeletedPromptWritesNothing() {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let seededCount = store.prompts.count
        var draft = PromptDraft(prompt: Prompt(title: "gone", content: "x"))
        draft.content = "y"
        #expect(store.savePrompt(draft) == nil)
        #expect(store.prompts.count == seededCount)
    }
}
