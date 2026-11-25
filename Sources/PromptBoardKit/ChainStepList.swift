import Foundation

public struct ChainStepList: Equatable, Sendable {
    public enum Row: Equatable, Sendable {
        case ready(title: String, text: String)
        case missing
    }

    public enum Activation: Equatable, Sendable {
        case paste(text: String, nextIndex: Int)
        case restart
        case nothing
    }

    public let chain: Chain
    public let rows: [Row]
    public let progressIndex: Int
    public private(set) var selectedIndex: Int?

    public init(chain: Chain, prompts: [Prompt], progressIndex: Int) {
        let promptsByID = Dictionary(prompts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.chain = chain
        self.progressIndex = progressIndex
        rows = chain.steps.map { step in
            switch step {
            case .linked(let promptID):
                guard let prompt = promptsByID[promptID] else { return .missing }
                return .ready(title: prompt.title, text: prompt.content)
            case .custom(let text):
                // isNewline, not "\n": Swift keeps "\r\n" as one Character that never equals "\n".
                let firstLine = text.split(whereSeparator: \.isNewline)
                    .first { !$0.allSatisfy(\.isWhitespace) }.map(String.init) ?? ""
                return .ready(title: firstLine, text: text)
            }
        }
        selectedIndex = readyIndices.first { $0 >= progressIndex }
    }

    private var readyIndices: [Int] {
        rows.indices.filter { if case .ready = rows[$0] { true } else { false } }
    }

    public var isEmpty: Bool { readyIndices.isEmpty }

    public var isDone: Bool { !isEmpty && selectedIndex == nil }

    public mutating func moveDown() {
        guard let selectedIndex else { return }
        if let next = readyIndices.first(where: { $0 > selectedIndex }) { self.selectedIndex = next }
    }

    public mutating func moveUp() {
        guard let selectedIndex else {
            self.selectedIndex = readyIndices.last
            return
        }
        if let previous = readyIndices.last(where: { $0 < selectedIndex }) { self.selectedIndex = previous }
    }

    public mutating func select(_ index: Int) {
        if readyIndices.contains(index) { selectedIndex = index }
    }

    public func activate() -> Activation {
        if isEmpty { return .nothing }
        guard let selectedIndex, case .ready(_, let text) = rows[selectedIndex] else { return .restart }
        return .paste(text: text, nextIndex: selectedIndex + 1)
    }
}
