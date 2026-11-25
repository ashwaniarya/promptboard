import Testing
@testable import PromptBoardKit

struct ClipboardHistoryTests {
    @Test func newestCopyComesFirst() {
        var history = ClipboardHistory()
        history.record("first")
        history.record("second")
        #expect(history.items == ["second", "first"])
    }

    @Test func repeatedCopyMovesToTopWithoutDuplicate() {
        var history = ClipboardHistory()
        history.record("a")
        history.record("b")
        history.record("a")
        #expect(history.items == ["a", "b"])
    }

    @Test func emptyAndWhitespaceCopiesAreIgnored() {
        var history = ClipboardHistory()
        history.record("")
        history.record("  \n\t ")
        #expect(history.items.isEmpty)
    }

    @Test func keepsOnlyTheNewestFifty() {
        var history = ClipboardHistory()
        for number in 1...55 { history.record("item \(number)") }
        #expect(history.items.count == 50)
        #expect(history.items.first == "item 55")
        #expect(history.items.last == "item 6")
    }

    @Test func emptyQueryMatchesEverything() {
        var history = ClipboardHistory()
        history.record("one")
        history.record("two")
        #expect(history.matches("  ") == ["two", "one"])
    }

    @Test func queryFiltersCaseInsensitively() {
        var history = ClipboardHistory()
        history.record("Hello World")
        history.record("goodbye")
        history.record("say hello")
        #expect(history.matches("HELLO") == ["say hello", "Hello World"])
    }
}
