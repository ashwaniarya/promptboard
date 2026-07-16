import Foundation

public enum MasonryLayout {
    public static func distribute<Item>(
        _ items: [Item],
        columns: Int,
        estimatedHeight: (Item) -> Double
    ) -> [[Item]] {
        guard columns > 0 else { return [] }
        var columnItems = Array(repeating: [Item](), count: columns)
        var columnHeights = Array(repeating: 0.0, count: columns)
        for item in items {
            let shortestColumn = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] }!
            columnItems[shortestColumn].append(item)
            columnHeights[shortestColumn] += estimatedHeight(item)
        }
        return columnItems
    }

    public static func estimatedCardHeight(
        title: String,
        content: String,
        cardWidth: Double,
        maxContentLines: Int = 12
    ) -> Double {
        let charactersPerLine = max(10.0, cardWidth / 7.0)
        let segments = content.split(separator: "\n", omittingEmptySubsequences: false)
        let wrappedLines = segments.reduce(0.0) { total, segment in
            total + max(1.0, (Double(segment.count) / charactersPerLine).rounded(.up))
        }
        let visibleLines = min(wrappedLines, Double(maxContentLines))
        let chromeHeight = 52.0
        let lineHeight = 18.0
        return chromeHeight + visibleLines * lineHeight
    }
}
