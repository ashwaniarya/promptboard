import Foundation
import Testing
@testable import PromptBoardKit

struct ChainModelTests {
    @Test func renderParseRoundTripsMixedSteps() {
        let steps: [Chain.Step] = [
            .linked(promptID: UUID()), .custom(text: "Write the spec\n\nThen stop."), .linked(promptID: UUID()),
        ]
        #expect(ChainBody.parse(ChainBody.render(steps)) == steps)
    }

    @Test func renderWritesHumanEditableSyntax() {
        let id = UUID()
        #expect(ChainBody.render([.linked(promptID: id)]) == "- @\(id.uuidString)")
        #expect(ChainBody.render([.custom(text: "hi")]) == "```\nhi\n```")
    }

    @Test func customStepContainingBackticksUsesLongerFence() {
        let steps: [Chain.Step] = [.custom(text: "use ```swift``` here")]
        let rendered = ChainBody.render(steps)
        #expect(rendered.contains("````\n"))
        #expect(ChainBody.parse(rendered) == steps)
    }

    @Test func parseIgnoresProseAndInvalidLinks() {
        let id = UUID()
        #expect(ChainBody.parse("intro\n- @not-a-uuid\n- @\(id.uuidString)") == [.linked(promptID: id)])
    }

    @Test func unclosedFenceKeepsRestAsCustomStep() {
        #expect(ChainBody.parse("```\nline one\nline two") == [.custom(text: "line one\nline two")])
    }

    @Test func parseEmptyBodyGivesNoSteps() {
        #expect(ChainBody.parse("") == [])
    }

    @Test func stepsSurviveFrontmatterRoundTrip() {
        let steps: [Chain.Step] = [.custom(text: "first"), .linked(promptID: UUID()), .custom(text: "a\n\nb")]
        let text = Frontmatter.render(fields: [("kind", "chain")], body: ChainBody.render(steps))
        #expect(ChainBody.parse(Frontmatter.parse(text).body) == steps)
    }
}
