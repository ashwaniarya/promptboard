import SwiftUI
import PromptBoardKit

struct PromptCardView: View {
    let item: LibraryEntry
    let appState: AppState

    @State private var isHovering = false
    @State private var justCopied = false
    @State private var copiedResetTask: Task<Void, Never>?

    private var isSkill: Bool { item.kind == .skill }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if isSkill {
                    Text("skill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
            }
            Text(item.previewText.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isHovering ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(isHovering ? 0.22 : 0.10))
        )
        .overlay(copiedBadge)
        .overlay(alignment: .topTrailing) { deleteButton }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded { beginEditingIfPrompt() }
                .exclusively(before: TapGesture(count: 1).onEnded { copyItem() })
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var copiedBadge: some View {
        if justCopied {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied")
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var deleteButton: some View {
        if isHovering {
            Button {
                appState.deleteItem(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(6)
            .transition(.opacity)
            .help(isSkill ? "Delete skill" : "Delete prompt")
        }
    }

    private func beginEditingIfPrompt() {
        // Skill editing arrives in Layer C; for now a skill's double-click copies like a single tap.
        if case .prompt(let prompt) = item {
            appState.beginEditing(prompt)
        } else {
            copyItem()
        }
    }

    private func copyItem() {
        appState.copyToClipboard(item)
        withAnimation(.spring(duration: 0.25)) { justCopied = true }
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { justCopied = false }
        }
    }
}
