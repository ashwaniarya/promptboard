import SwiftUI
import PromptBoardKit

// Compact caret popup: a slash search field over a keyboard-navigable list of
// prompts. Typing goes to the field; ↑↓/⏎/esc are handled by the controller's
// key monitor (SwiftUI focus is unreliable in a non-activating panel). Tap inserts.
struct QuickInsertView: View {
    @Bindable var model: QuickInsertModel
    let onInsert: (Prompt) -> Void

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
        if model.results.isEmpty {
            Text(model.query.isEmpty ? "No prompts to insert" : "No matches")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, prompt in
                    row(prompt, index: index)
                }
            }
            .padding(6)
        }
    }

    private func row(_ prompt: Prompt, index: Int) -> some View {
        let selected = index == model.selectedIndex
        return HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13)).frame(width: 16)
                .foregroundStyle(selected ? accent : Color.white.opacity(0.55))
            VStack(alignment: .leading, spacing: 1) {
                Text(prompt.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(prompt.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("/\(Slug.make(from: prompt.title))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(selected ? accent : Color.white.opacity(0.4)).lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.82))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.20) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedIndex = index
            onInsert(prompt)
        }
    }
}
