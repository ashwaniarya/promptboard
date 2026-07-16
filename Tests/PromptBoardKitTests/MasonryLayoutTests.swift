import Foundation
import Testing
@testable import PromptBoardKit

struct MasonryLayoutTests {
    @Test func everyItemAppearsExactlyOnce() {
        let items = Array(0..<25)
        let columns = MasonryLayout.distribute(items, columns: 3) { _ in 100 }

        let flattened = columns.flatMap { $0 }.sorted()
        #expect(flattened == items)
    }

    @Test func relativeOrderPreservedWithinEachColumn() {
        let items = Array(0..<40)
        let columns = MasonryLayout.distribute(items, columns: 4) { Double($0 % 7) * 30 + 50 }

        for column in columns {
            #expect(column == column.sorted())
        }
    }

    @Test func equalHeightsBalanceCountsWithinOne() {
        let items = Array(0..<22)
        let columns = MasonryLayout.distribute(items, columns: 4) { _ in 80 }

        let counts = columns.map(\.count)
        #expect(counts.max()! - counts.min()! <= 1)
    }

    @Test func tallItemColumnReceivesFewerItems() {
        let items = Array(0..<10)
        let columns = MasonryLayout.distribute(items, columns: 2) { $0 == 0 ? 1000.0 : 100.0 }

        let tallColumn = columns.first { $0.contains(0) }!
        let otherColumn = columns.first { !$0.contains(0) }!
        #expect(tallColumn.count < otherColumn.count)
    }

    @Test func singleColumnReceivesEverythingInOrder() {
        let items = Array(0..<8)
        let columns = MasonryLayout.distribute(items, columns: 1) { _ in 50 }

        #expect(columns.count == 1)
        #expect(columns[0] == items)
    }

    @Test func degenerateInputsAreSafe() {
        #expect(MasonryLayout.distribute([Int](), columns: 3) { _ in 10.0 } == [[], [], []])
        #expect(MasonryLayout.distribute([1, 2, 3], columns: 0) { _ in 10.0 }.isEmpty)
    }

    @Test func longerContentEstimatesTallerCard() {
        let short = MasonryLayout.estimatedCardHeight(title: "T", content: "one line", cardWidth: 300)
        let long = MasonryLayout.estimatedCardHeight(
            title: "T",
            content: String(repeating: "many words in this prompt ", count: 20),
            cardWidth: 300
        )
        #expect(long > short)
    }

    @Test func estimatedHeightIsCappedAtMaxLines() {
        let huge = MasonryLayout.estimatedCardHeight(
            title: "T",
            content: String(repeating: "x", count: 100_000),
            cardWidth: 300
        )
        let alsoHuge = MasonryLayout.estimatedCardHeight(
            title: "T",
            content: String(repeating: "y", count: 200_000),
            cardWidth: 300
        )
        #expect(huge == alsoHuge)
    }

    @Test func hardNewlinesCountAsLines() {
        let multiline = MasonryLayout.estimatedCardHeight(title: "T", content: "a\nb\nc\nd", cardWidth: 300)
        let single = MasonryLayout.estimatedCardHeight(title: "T", content: "a", cardWidth: 300)
        #expect(multiline > single)
    }
}
