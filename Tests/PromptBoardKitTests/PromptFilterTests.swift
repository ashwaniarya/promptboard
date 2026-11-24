import Foundation
import Testing
@testable import PromptBoardKit

struct PromptFilterTests {
    private let prompts = [
        Prompt(title: "Code Review", content: "Review this code for bugs"),
        Prompt(title: "Café Order", content: "Order a flat white"),
        Prompt(title: "Meeting Notes", content: "Summarize KEY decisions"),
    ]

    private let externalItems = [
        ExternalItem(name: "trello-card-reader", kind: .skill, origin: "Claude Code",
                     url: URL(fileURLWithPath: "/x/trello-card-reader")),
        ExternalItem(name: "vercel-deploy", kind: .skill, origin: "Codex",
                     url: URL(fileURLWithPath: "/x/vercel-deploy")),
    ]

    @Test func emptyQueryReturnsAllPrompts() {
        #expect(PromptFilter.filter(prompts, query: "").count == 3)
    }

    @Test func emptyQueryReturnsAllExternalItems() {
        #expect(PromptFilter.filter(externalItems, query: "").count == 2)
    }

    @Test func matchesExternalItemByName() {
        let result = PromptFilter.filter(externalItems, query: "trello")
        #expect(result.map(\.name) == ["trello-card-reader"])
    }

    @Test func matchesExternalItemByOriginCaseInsensitively() {
        let result = PromptFilter.filter(externalItems, query: "codex")
        #expect(result.map(\.name) == ["vercel-deploy"])
    }

    @Test func nonMatchingQueryReturnsNoExternalItems() {
        #expect(PromptFilter.filter(externalItems, query: "nonexistent").isEmpty)
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

    // MARK: - quickInsertResults over mixed entries

    private let shipChain = Chain(title: "Ship", steps: [.custom(text: "Write the spec\n\nThen stop.")])

    @Test func mixedResultsDropSkills() {
        let prompt = LibraryEntry.prompt(Prompt(title: "A", content: "a"))
        let chain = LibraryEntry.chain(shipChain)
        let skill = LibraryEntry.skill(Skill(name: "s", description: "d", body: "b"))

        #expect(PromptFilter.quickInsertResults([prompt, skill, chain], query: "") == [prompt, chain])
    }

    @Test func chainRanksByAliasLikePrompts() {
        let prompt = LibraryEntry.prompt(Prompt(title: "Deploy", content: "ship it now"))
        let chain = LibraryEntry.chain(shipChain)

        #expect(PromptFilter.quickInsertResults([prompt, chain], query: "/ship") == [chain, prompt])
    }

    @Test func chainMatchesCustomStepText() {
        let chain = LibraryEntry.chain(shipChain)

        #expect(PromptFilter.quickInsertResults([chain], query: "stop.") == [chain])
    }

    @Test func chainDoesNotMatchLinkedPromptContent() {
        let linked = Prompt(title: "Spec", content: "only-in-linked-prompt")
        let prompt = LibraryEntry.prompt(linked)
        let chain = LibraryEntry.chain(Chain(title: "Ship", steps: [.linked(promptID: linked.id)]))

        #expect(PromptFilter.quickInsertResults([chain, prompt], query: "only-in-linked") == [prompt])
    }

    @Test func stableWithinTierAcrossKinds() {
        let chain = LibraryEntry.chain(Chain(title: "Big Review Flow", steps: []))
        let prompt = LibraryEntry.prompt(Prompt(title: "Quick Review", content: "x"))

        #expect(PromptFilter.quickInsertResults([chain, prompt], query: "review") == [chain, prompt])
        #expect(PromptFilter.quickInsertResults([prompt, chain], query: "review") == [prompt, chain])
    }
}
