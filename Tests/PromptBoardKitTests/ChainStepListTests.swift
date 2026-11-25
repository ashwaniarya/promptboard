import Foundation
import Testing
@testable import PromptBoardKit

struct ChainStepListTests {
    private let spec = Prompt(title: "Spec", content: "write the spec")
    private let plan = Prompt(title: "Plan", content: "write the plan")

    private func list(_ steps: [Chain.Step], progress: Int = 0, prompts: [Prompt]? = nil) -> ChainStepList {
        ChainStepList(chain: Chain(title: "Ship", steps: steps), prompts: prompts ?? [spec, plan], progressIndex: progress)
    }

    private var threeSteps: [Chain.Step] {
        [.linked(promptID: spec.id), .linked(promptID: plan.id), .custom(text: "review\nit all")]
    }

    @Test func freshChainSelectsFirstStep() {
        #expect(list(threeSteps).selectedIndex == 0)
    }

    @Test func progressIndexSelectsThatStep() {
        #expect(list(threeSteps, progress: 2).selectedIndex == 2)
    }

    @Test func missingLinkedStepIsSkipped() {
        let stepList = list([.linked(promptID: UUID()), .custom(text: "b")])
        #expect(stepList.rows[0] == .missing)
        #expect(stepList.selectedIndex == 1)
    }

    @Test func linkedStepUsesCurrentPromptContent() {
        var edited = spec
        edited.content = "v2"
        let stepList = list([.linked(promptID: spec.id)], prompts: [edited])
        #expect(stepList.rows[0] == .ready(title: spec.title, text: "v2"))
    }

    @Test func customStepTitleIsFirstLine() {
        #expect(list(threeSteps).rows[2] == .ready(title: "review", text: "review\nit all"))
    }

    @Test func activatePastesAndAdvances() {
        #expect(list(threeSteps, progress: 1).activate() == .paste(text: "write the plan", nextIndex: 2))
    }

    @Test func arrowPickJumpsProgress() {
        var stepList = list(threeSteps)
        stepList.moveDown()
        stepList.moveDown()
        #expect(stepList.activate() == .paste(text: "review\nit all", nextIndex: 3))
    }

    @Test func moveSkipsMissingRows() {
        var stepList = list([.custom(text: "a"), .linked(promptID: UUID()), .custom(text: "c")])
        stepList.moveDown()
        #expect(stepList.selectedIndex == 2)
        stepList.moveDown()
        #expect(stepList.selectedIndex == 2)
    }

    @Test func pastLastStepIsDoneAndRestarts() {
        let stepList = list(threeSteps, progress: 3)
        #expect(stepList.isDone)
        #expect(stepList.activate() == .restart)
    }

    @Test func missingTrailingStepsCountAsDone() {
        #expect(list([.custom(text: "a"), .linked(promptID: UUID())], progress: 1).isDone)
    }

    @Test func emptyChainCannotActivate() {
        for stepList in [list([]), list([.linked(promptID: UUID())])] {
            #expect(stepList.isEmpty)
            #expect(!stepList.isDone)
            #expect(stepList.activate() == .nothing)
        }
    }

    @Test func moveUpFromDoneSelectsLastReadyStep() {
        var stepList = list([.custom(text: "a"), .custom(text: "b"), .linked(promptID: UUID())], progress: 3)
        stepList.moveUp()
        #expect(stepList.selectedIndex == 1)
        stepList.moveUp()
        #expect(stepList.selectedIndex == 0)
        stepList.moveUp()
        #expect(stepList.selectedIndex == 0)
    }

    @Test func selectPicksOnlyReadyRows() {
        var stepList = list([.custom(text: "a"), .linked(promptID: UUID()), .custom(text: "c")])
        stepList.select(1)
        #expect(stepList.selectedIndex == 0)
        stepList.select(2)
        #expect(stepList.activate() == .paste(text: "c", nextIndex: 3))
    }

    private func snapshot(_ root: URL) -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            files[String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count))] = try? Data(contentsOf: url)
        }
        return files
    }

    @Test func fullRunLeavesLibraryFilesByteIdentical() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardChainRunTests-\(UUID().uuidString)", isDirectory: true)
        let repository = LibraryRepository(directoryURL: directory, syncTargets: .temporary())
        let first = try repository.addPrompt(title: "Spec", content: "write the spec")
        let second = try repository.addPrompt(title: "Plan", content: "write the plan")
        let chain = try repository.addChain(
            title: "Ship", steps: [.linked(promptID: first.id), .custom(text: "review"), .linked(promptID: second.id)]
        )
        let progress = ChainProgress(fileURL: repository.chainStateURL)
        let libraryBefore = snapshot(repository.libraryURL)
        let dataDirBefore = snapshot(directory)

        var pasted: [String] = []
        while true {
            let stepList = ChainStepList(
                chain: chain, prompts: [first, second],
                progressIndex: progress.index(for: chain.id, stepCount: chain.steps.count)
            )
            guard case .paste(let text, let nextIndex) = stepList.activate() else { break }
            pasted.append(text)
            try progress.setIndex(nextIndex, for: chain.id)
        }

        #expect(pasted == ["write the spec", "review", "write the plan"])
        #expect(snapshot(repository.libraryURL) == libraryBefore)
        let dataDirAfter = snapshot(directory)
        let changed = Set(dataDirAfter.keys).union(dataDirBefore.keys).filter { dataDirAfter[$0] != dataDirBefore[$0] }
        #expect(changed == ["/chain-state.json"])
    }
}
