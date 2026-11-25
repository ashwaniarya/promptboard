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
}
