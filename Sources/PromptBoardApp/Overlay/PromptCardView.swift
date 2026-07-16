import SwiftUI
import PromptBoardKit

struct PromptCardView: View {
    let prompt: Prompt
    let appState: AppState

    @State private var isHovering = false
    @State private var justCopied = false
    @State private var copiedResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt.title)
                .font(.headline)
                .lineLimit(2)
            Text(prompt.content.trimmingCharacters(in: .whitespacesAndNewlines))
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
            TapGesture(count: 2).onEnded { appState.beginEditing(prompt) }
                .exclusively(before: TapGesture(count: 1).onEnded { copyPrompt() })
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
                appState.deletePrompt(id: prompt.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85), .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(6)
            .transition(.opacity)
            .help("Delete prompt")
        }
    }

    private func copyPrompt() {
        appState.copyToClipboard(prompt)
        withAnimation(.spring(duration: 0.25)) { justCopied = true }
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { justCopied = false }
        }
    }
}
