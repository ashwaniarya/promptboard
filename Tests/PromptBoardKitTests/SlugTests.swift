import Testing
@testable import PromptBoardKit

struct SlugTests {
    @Test func kebabCasesTitles() {
        #expect(Slug.make(from: "Code Review") == "code-review")
        #expect(Slug.make(from: "Trello Card Reader") == "trello-card-reader")
    }

    @Test func stripsPunctuationAndCollapsesSeparators() {
        #expect(Slug.make(from: "Hello, World!") == "hello-world")
        #expect(Slug.make(from: "  spaced   out  ") == "spaced-out")
        #expect(Slug.make(from: "a__b--c") == "a-b-c")
    }

    @Test func leavesCleanSlugsUnchanged() {
        #expect(Slug.make(from: "already-kebab") == "already-kebab")
    }

    @Test func emptyOrSymbolOnlyFallsBackToUntitled() {
        #expect(Slug.make(from: "") == "untitled")
        #expect(Slug.make(from: "!!! ???") == "untitled")
    }

    @Test func uniqueReturnsBaseWhenFree() {
        #expect(Slug.unique("foo", existing: []) == "foo")
    }

    @Test func uniqueSuffixesOnCollision() {
        #expect(Slug.unique("foo", existing: ["foo"]) == "foo-2")
        #expect(Slug.unique("foo", existing: ["foo", "foo-2"]) == "foo-3")
    }
}
