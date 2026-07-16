import Foundation
import Testing
@testable import PromptBoardKit

struct PromptFilterTests {
    private let prompts = [
        Prompt(title: "Code Review", content: "Review this code for bugs"),
        Prompt(title: "Café Order", content: "Order a flat white"),
        Prompt(title: "Meeting Notes", content: "Summarize KEY decisions"),
    ]

    @Test func emptyQueryReturnsAllPrompts() {
        #expect(PromptFilter.filter(prompts, query: "").count == 3)
    }

    @Test func whitespaceOnlyQueryReturnsAllPrompts() {
        #expect(PromptFilter.filter(prompts, query: "   \n ").count == 3)
    }

    @Test func matchesTitleCaseInsensitively() {
        let result = PromptFilter.filter(prompts, query: "code review")
        #expect(result.map(\.title) == ["Code Review"])
    }

    @Test func matchesContentCaseInsensitively() {
        let result = PromptFilter.filter(prompts, query: "key decisions")
        #expect(result.map(\.title) == ["Meeting Notes"])
    }

    @Test func matchesDiacriticInsensitively() {
        let result = PromptFilter.filter(prompts, query: "cafe")
        #expect(result.map(\.title) == ["Café Order"])
    }

    @Test func noMatchReturnsEmpty() {
        #expect(PromptFilter.filter(prompts, query: "zebra").isEmpty)
    }
}
