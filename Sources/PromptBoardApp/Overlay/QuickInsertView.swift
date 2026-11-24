import SwiftUI
import PromptBoardKit

// Compact caret popup: a slash search field over a keyboard-navigable list of
// prompts and chains, or an open chain's steps. Typing goes to the field; ↑↓/⏎/esc are
// handled by the controller's key monitor (SwiftUI focus is unreliable in a non-activating panel). Tap activates.
struct QuickInsertView: View {
    @Bindable var model: QuickInsertModel
    let onActivate: () -> Void

    static let searchPlaceholder = "insert a prompt…"
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            results
        }
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.13)))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Text("/").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
            TextField(Self.searchPlaceholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            Spacer(minLength: 6)
            Text("\(model.results.count)")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
    }

    @ViewBuilder
    private var results: some View {
        if let stepList = model.stepList {
            stepListView(stepList)
        } else if model.results.isEmpty {
            Text(model.query.isEmpty ? "No prompts to insert" : "No matches")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
            }
            .padding(6)
        }
    }

    private func row(_ entry: LibraryEntry, index: Int) -> some View {
        let selected = index == model.selectedIndex
        let emptyChain: Bool
        let subtitle: String
        switch entry {
        case .chain(let chain):
            emptyChain = model.stepList(for: chain).isEmpty
            subtitle = emptyChain ? "no steps" : "\(chain.steps.count) steps"
        default:
            emptyChain = false
            subtitle = entry.previewText.replacingOccurrences(of: "\n", with: " ")
        }
        return HStack(spacing: 10) {
            Image(systemName: entry.kind == .chain ? "list.number" : "doc.text")
                .font(.system(size: 13)).frame(width: 16)
                .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("/\(Slug.make(from: entry.title))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(selected ? accent : Color.white.opacity(0.4)).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.82))
        .opacity(emptyChain ? 0.45 : 1)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedIndex = index
            onActivate()
        }
    }

    private func stepListView(_ stepList: ChainStepList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").foregroundStyle(accent)
                Text(stepList.chain.title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text("esc back").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            ForEach(Array(stepList.rows.enumerated()), id: \.offset) { index, row in
                stepRow(row, index: index, selected: index == stepList.selectedIndex)
            }
            if stepList.isDone {
                Text("done · ⏎ restarts")
                    .font(.system(size: 11)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(6)
    }

    private func stepRow(_ row: ChainStepList.Row, index: Int, selected: Bool) -> some View {
        let title: String
        let isMissing: Bool
        switch row {
        case .ready(let readyTitle, _): title = readyTitle; isMissing = false
        case .missing: title = "missing"; isMissing = true
        }
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, design: .monospaced)).frame(width: 16)
                .foregroundStyle(selected ? accent : Color.white.opacity(0.45))
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                .italic(isMissing)
            Spacer(minLength: 6)
        }
        .foregroundStyle(isMissing ? Color.white.opacity(0.35) : selected ? Color.white : Color.white.opacity(0.82))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMissing else { return }
            model.selectStep(index)
            onActivate()
        }
    }
}
