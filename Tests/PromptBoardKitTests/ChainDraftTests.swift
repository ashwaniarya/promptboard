import Foundation
import Testing
@testable import PromptBoardKit

struct ChainDraftTests {
    private let spec = Prompt(title: "Spec", content: "write the spec")
    private let plan = Prompt(title: "Plan", content: "write the plan")
    private var items: [LibraryEntry] {
        [.prompt(spec), .prompt(plan), .chain(Chain(title: "Spec chain", steps: []))]
    }

    private func draft(_ steps: [Chain.Step]) -> ChainDraft {
        ChainDraft(chain: Chain(title: "Ship", steps: steps))
    }

    @Test func newDraftIsEmptyAndUnsavable() {
        let draft = ChainDraft()
        #expect(draft.chainID == nil)
        #expect(draft.steps.isEmpty)
        #expect(draft.selectedStep == nil)
        #expect(!draft.canSave)
    }

    @Test func editDraftCopiesChainAndSelectsFirstStep() {
        let chain = Chain(title: "Ship", steps: [.custom(text: "a"), .custom(text: "b")])
        let draft = ChainDraft(chain: chain)
        #expect(draft.chainID == chain.id)
        #expect(draft.title == "Ship")
        #expect(draft.steps == chain.steps)
        #expect(draft.selectedStep == 0)
        #expect(draft.canSave)
    }

    @Test func canSaveNeedsTitleAndNoBlankCustomStep() {
        var draft = ChainDraft()
        draft.title = "  "
        #expect(!draft.canSave)
        draft.title = "Ship"
        #expect(draft.canSave)
        draft.addLinked(spec.id)
        draft.addCustom("x")
        draft.setCustomText(" \n", at: 1)
        #expect(!draft.canSave)
    }

    @Test func pickerListsPromptsOnlyThenCustomRow() {
        var draft = ChainDraft()
        draft.query = "spec"
        #expect(draft.pickerRows(in: items) == [.prompt(spec), .custom("spec")])
    }

    @Test func pickerWithoutQueryHasNoCustomRow() {
        #expect(ChainDraft().pickerRows(in: items) == [.prompt(spec), .prompt(plan)])
    }

    @Test func pickerCapsPromptsButKeepsCustomRowLast() {
        let many = (0..<10).map { LibraryEntry.prompt(Prompt(title: "Note \($0)", content: "")) }
        var draft = ChainDraft()
        draft.query = "note"
        let rows = draft.pickerRows(in: many)
        #expect(rows.count == ChainDraft.pickerPromptLimit + 1)
        #expect(rows.last == .custom("note"))
    }

    @Test func movePickerClampsToRows() {
        var draft = ChainDraft()
        draft.movePicker(by: -1, in: items)
        #expect(draft.pickerIndex == 0)
        draft.movePicker(by: 5, in: items)
        #expect(draft.pickerIndex == 1)
    }

    @Test func queryChangeResetsPicker() {
        var draft = ChainDraft()
        draft.movePicker(by: 1, in: items)
        draft.query = "p"
        #expect(draft.pickerIndex == 0)
    }

    @Test func addPickedPromptAppendsLinkedStepAndClearsQuery() {
        var draft = ChainDraft()
        draft.query = "pla"
        draft.addPicked(in: items)
        #expect(draft.steps == [.linked(promptID: plan.id)])
        #expect(draft.selectedStep == 0)
        #expect(draft.query == "")
    }

    @Test func addPickedCustomRowAppendsTypedText() {
        var draft = ChainDraft()
        draft.query = "spec"
        draft.movePicker(by: 1, in: items)
        draft.addPicked(in: items)
        #expect(draft.steps == [.custom(text: "spec")])
    }

    @Test func addPickedWithNoRowsDoesNothing() {
        var draft = ChainDraft()
        draft.addPicked(in: [])
        #expect(draft.steps.isEmpty)
    }

    @Test func addCustomTrimsAndIgnoresBlank() {
        var draft = ChainDraft()
        draft.addCustom("   ")
        #expect(draft.steps.isEmpty)
        draft.query = "  review it \n"
        draft.addCustom(draft.query)
        #expect(draft.steps == [.custom(text: "review it")])
        #expect(draft.query == "")
    }

    @Test func addSelectsTheNewStep() {
        var draft = draft([.custom(text: "a"), .custom(text: "b")])
        draft.addLinked(spec.id)
        #expect(draft.selectedStep == 2)
    }

    @Test func setCustomTextIgnoresLinkedAndOutOfRange() {
        var draft = draft([.linked(promptID: spec.id)])
        draft.setCustomText("x", at: 0)
        draft.setCustomText("x", at: 4)
        #expect(draft.steps == [.linked(promptID: spec.id)])
    }

    @Test func moveSelectedStepSwapsAndFollows() {
        var draft = draft([.custom(text: "a"), .custom(text: "b"), .custom(text: "c")])
        draft.moveSelectedStep(by: 1)
        #expect(draft.steps == [.custom(text: "b"), .custom(text: "a"), .custom(text: "c")])
        #expect(draft.selectedStep == 1)
        draft.moveSelectedStep(by: -1)
        #expect(draft.selectedStep == 0)
        #expect(draft.steps.first == .custom(text: "a"))
    }

    @Test func moveSelectedStepStopsAtEdges() {
        var draft = draft([.custom(text: "a"), .custom(text: "b")])
        draft.moveSelectedStep(by: -1)
        #expect(draft.steps == [.custom(text: "a"), .custom(text: "b")])
        draft.selectStep(1)
        draft.moveSelectedStep(by: 1)
        #expect(draft.steps == [.custom(text: "a"), .custom(text: "b")])
        #expect(draft.selectedStep == 1)
    }

    @Test func selectStepIgnoresOutOfRange() {
        var draft = draft([.custom(text: "a")])
        draft.selectStep(3)
        #expect(draft.selectedStep == 0)
    }

    @Test func removeSelectedStepKeepsANeighbourSelected() {
        var draft = draft([.custom(text: "a"), .custom(text: "b"), .custom(text: "c")])
        draft.selectStep(2)
        draft.removeSelectedStep()
        #expect(draft.steps == [.custom(text: "a"), .custom(text: "b")])
        #expect(draft.selectedStep == 1)
        draft.selectStep(0)
        draft.removeSelectedStep()
        #expect(draft.steps == [.custom(text: "b")])
        #expect(draft.selectedStep == 0)
        draft.removeSelectedStep()
        #expect(draft.steps.isEmpty)
        #expect(draft.selectedStep == nil)
        draft.removeSelectedStep()
        #expect(draft.steps.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardChainDraftTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test @MainActor func saveNewDraftAddsChain() throws {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        var draft = ChainDraft()
        draft.title = "Ship"
        draft.addCustom("review it")

        let saved = try #require(store.saveChain(draft))

        #expect(store.chains.map(\.id) == [saved.id])
        #expect(saved.title == "Ship")
        #expect(saved.steps == [.custom(text: "review it")])
    }

    @Test @MainActor func saveEditDraftUpdatesSameChain() throws {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let chain = try #require(store.addChain(title: "Ship", steps: [.custom(text: "a")]))
        var draft = ChainDraft(chain: chain)
        draft.title = "Ship it"
        draft.addCustom("b")
        draft.moveSelectedStep(by: -1)

        let saved = try #require(store.saveChain(draft))

        #expect(saved.id == chain.id)
        #expect(store.chains.count == 1)
        #expect(store.chains.first?.title == "Ship it")
        #expect(store.chains.first?.steps == [.custom(text: "b"), .custom(text: "a")])
    }

    @Test @MainActor func saveEditDraftOfDeletedChainFailsWithoutWriting() throws {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        let chain = try #require(store.addChain(title: "Ship", steps: []))
        store.delete(id: chain.id)

        #expect(store.saveChain(ChainDraft(chain: chain)) == nil)
        #expect(store.chains.isEmpty)
    }

    @Test @MainActor func unsavableDraftIsNotWritten() {
        let store = LibraryStore(directoryURL: temporaryDirectory(), syncTargets: .temporary())
        #expect(store.saveChain(ChainDraft()) == nil)
        #expect(store.chains.isEmpty)
    }
}
