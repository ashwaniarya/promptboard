import Foundation
import Testing
@testable import PromptBoardKit

struct ChainProgressViewTests {
    private let spec = Prompt(title: "Spec", content: "write the spec")
    private let plan = Prompt(title: "Plan", content: "write the plan")

    private func view(_ steps: [Chain.Step], progress: Int = 0) -> ChainProgressView {
        ChainProgressView(chain: Chain(title: "Ship", steps: steps), prompts: [spec, plan], progressIndex: progress)
    }

    private var threeSteps: [Chain.Step] {
        [.linked(promptID: spec.id), .linked(promptID: plan.id), .custom(text: "review\nit all")]
    }

    @Test func freshChainFirstSegmentIsCurrent() {
        let progressView = view(threeSteps)
        #expect(progressView.segments == [.current, .upcoming, .upcoming])
        #expect(progressView.completedCount == 0)
        #expect(progressView.currentIndex == 0)
    }

    @Test func middleProgressMarksDoneBeforeCurrent() {
        let progressView = view(threeSteps, progress: 2)
        #expect(progressView.segments == [.done, .done, .current])
        #expect(progressView.completedCount == 2)
    }

    @Test func finishedChainIsAllDone() {
        let progressView = view(threeSteps, progress: 3)
        #expect(progressView.segments == [.done, .done, .done])
        #expect(progressView.isDone)
        #expect(progressView.nextPreview == nil)
        #expect(progressView.completedCount == 3)
    }

    @Test func missingAtProgressIsNeverCurrent() {
        let progressView = view([.linked(promptID: UUID()), .custom(text: "b")])
        #expect(progressView.segments == [.missing, .current])
        #expect(progressView.rowTags == [.missingSkipped, .now])
    }

    @Test func trailingMissingStepsReadAsDone() {
        let progressView = view([.custom(text: "a"), .linked(promptID: UUID())], progress: 1)
        #expect(progressView.isDone)
        #expect(progressView.segments == [.done, .missing])
    }

    @Test func emptyChainHasNoPreviewAndIsNotDone() {
        let progressView = view([.linked(promptID: UUID()), .linked(promptID: UUID())])
        #expect(progressView.isEmpty)
        #expect(!progressView.isDone)
        #expect(progressView.nextPreview == nil)
    }

    @Test func twelveStepsUseSegments() {
        #expect(!view(Array(repeating: .custom(text: "a"), count: 12)).usesContinuousBar)
    }

    @Test func thirteenStepsUseContinuousBar() {
        #expect(view(Array(repeating: .custom(text: "a"), count: 13)).usesContinuousBar)
    }

    @Test func previewOfLinkedStepIsPromptTitle() {
        #expect(view(threeSteps).nextPreview == "Spec")
    }

    @Test func previewSkipsLeadingBlankLines() {
        #expect(view([.custom(text: "\n\nreview\nit all")]).nextPreview == "review")
    }

    @Test func previewTruncatesAtSixtyCharacters() {
        let long = view([.custom(text: String(repeating: "x", count: 200))]).nextPreview
        #expect(long?.count == 60)
        #expect(long?.hasSuffix("…") == true)
        let exact = String(repeating: "x", count: 60)
        #expect(view([.custom(text: exact)]).nextPreview == exact)
    }

    @Test func rowTagsMarkLinkedAndCustom() {
        #expect(view(threeSteps, progress: 1).rowTags == [.linked, .now, .custom])
    }

    @Test func stepListExposesProgressIndex() {
        let chain = Chain(title: "Ship", steps: threeSteps)
        let stepList = ChainStepList(chain: chain, prompts: [spec, plan], progressIndex: 2)
        #expect(stepList.progressIndex == 2)
        #expect(ChainProgressView(stepList: stepList) == ChainProgressView(chain: chain, prompts: [spec, plan], progressIndex: 2))
    }
}
