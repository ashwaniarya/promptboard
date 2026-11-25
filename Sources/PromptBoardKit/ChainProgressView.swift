import Foundation

public struct ChainProgressView: Equatable, Sendable {
    public enum Segment: Equatable, Sendable { case done, current, upcoming, missing }
    public enum Tag: Equatable, Sendable { case now, linked, custom, missingSkipped }

    public static let continuousBarThreshold = 12
    public static let previewCharacterLimit = 60

    public let segments: [Segment]
    public let rowTags: [Tag]
    public let currentIndex: Int?
    public let nextPreview: String?

    public var stepCount: Int { segments.count }
    public var completedCount: Int { currentIndex ?? stepCount }
    public var isEmpty: Bool { !segments.contains { $0 != .missing } }
    public var isDone: Bool { !isEmpty && currentIndex == nil }
    public var usesContinuousBar: Bool { stepCount > Self.continuousBarThreshold }

    public init(chain: Chain, prompts: [Prompt], progressIndex: Int) {
        self.init(stepList: ChainStepList(chain: chain, prompts: prompts, progressIndex: progressIndex))
    }

    public init(stepList: ChainStepList) {
        // From stored progress, not selectedIndex: arrow picks move only the highlight.
        let currentIndex = stepList.rows.indices.first { index in
            guard index >= stepList.progressIndex, case .ready = stepList.rows[index] else { return false }
            return true
        }
        self.currentIndex = currentIndex
        segments = stepList.rows.indices.map { index in
            guard case .ready = stepList.rows[index] else { return .missing }
            guard let currentIndex else { return .done }
            if index < currentIndex { return .done }
            return index == currentIndex ? .current : .upcoming
        }
        rowTags = zip(stepList.rows.indices, stepList.chain.steps).map { index, step in
            if stepList.rows[index] == .missing { return .missingSkipped }
            if index == currentIndex { return .now }
            if case .linked = step { return .linked }
            return .custom
        }
        if let currentIndex, case .ready(let title, _) = stepList.rows[currentIndex] {
            nextPreview = title.count > Self.previewCharacterLimit
                ? String(title.prefix(Self.previewCharacterLimit - 1)) + "…"
                : title
        } else {
            nextPreview = nil
        }
    }
}
