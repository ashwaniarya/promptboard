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

    // MARK: - quickInsertResults (Layer D ranking)

    private let insertPrompts = [
        Prompt(title: "Rewrite Professionally", content: "Keep it professional and do a final review"),
        Prompt(title: "Code Review", content: "Review this code for bugs"),
        Prompt(title: "Product Launch", content: "Plan the launch"),
    ]

    @Test func quickInsertEmptyQueryReturnsAllInOrder() {
        let result = PromptFilter.quickInsertResults(insertPrompts, query: "  ")
        #expect(result.map(\.title) == ["Rewrite Professionally", "Code Review", "Product Launch"])
    }

    @Test func quickInsertExactSlashAliasRanksFirst() {
        #expect(PromptFilter.quickInsertResults(insertPrompts, query: "/code-review").map(\.title) == ["Code Review"])
        #expect(PromptFilter.quickInsertResults(insertPrompts, query: "code-review").map(\.title) == ["Code Review"])
    }

    @Test func quickInsertAliasPrefixMatches() {
        #expect(PromptFilter.quickInsertResults(insertPrompts, query: "product").map(\.title) == ["Product Launch"])
    }

    @Test func quickInsertTitleRanksAboveContent() {
        // "review": Code Review matches its title (tier 3); Rewrite Professionally only in content (tier 4)
        #expect(PromptFilter.quickInsertResults(insertPrompts, query: "review").map(\.title) == ["Code Review", "Rewrite Professionally"])
    }

    @Test func quickInsertAliasPrefixRanksAboveTitle() {
        // "pro": Product Launch alias-prefix (tier 2) beats Rewrite Professionally title (tier 3)
        #expect(PromptFilter.quickInsertResults(insertPrompts, query: "pro").map(\.title) == ["Product Launch", "Rewrite Professionally"])
    }

    @Test func quickInsertNoMatchReturnsEmpty() {
        #expect(PromptFilter.quickInsertResults(insertPrompts, query: "zebra").isEmpty)
    }
}
