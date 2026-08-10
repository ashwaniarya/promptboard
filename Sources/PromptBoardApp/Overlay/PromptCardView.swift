import SwiftUI
import PromptBoardKit

struct PromptCardView: View {
    let item: LibraryEntry
    let appState: AppState

    @State private var isHovering = false
    @State private var justCopied = false
    @State private var copiedResetTask: Task<Void, Never>?

    private let cardHeight: CGFloat = 168
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    private var isSkill: Bool { item.kind == .skill }
    private var skillFiles: [SkillFile] {
        if case .skill(let skill) = item { skill.files } else { [] }
    }

    // Overflowing preview text fades out instead of being hard-clipped mid-word.
    private var overflowFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            MarkdownText(
                markdown: MarkdownText.flattenedForPreview(
                    item.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask(overflowFade)
            .clipped()
            if !skillFiles.isEmpty { fileChips }
        }
        .padding(12)
        .frame(height: cardHeight, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isHovering ? 0.11 : 0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(
                isSkill ? accent.opacity(isHovering ? 0.55 : 0.30)
                        : .white.opacity(isHovering ? 0.20 : 0.09)
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(copiedBadge)
        .overlay(alignment: .topTrailing) { hoverActions }
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2).onEnded { beginEditOrExpand() }
                .exclusively(before: TapGesture(count: 1).onEnded { copyItem() })
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .draggable(item.id.uuidString)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isSkill {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(1)
            if isSkill {
                Text("skill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.16)))
            }
            Spacer(minLength: 0)
        }
    }

    private var fileChips: some View {
        HStack(spacing: 5) {
            ForEach(skillFiles.prefix(3), id: \.relativePath) { file in
                Text(file.relativePath)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            }
            if skillFiles.count > 3 {
                Text("+\(skillFiles.count - 3)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        if isHovering {
            HStack(spacing: 4) {
                if isSkill {
                    iconButton("pencil", help: "Edit skill") { editSkill() }
                } else {
                    iconButton("puzzlepiece.extension", help: "Convert to skill") { convertPrompt() }
                }
                iconButton("arrow.up.left.and.arrow.down.right", help: "Expand") { openDetail() }
                iconButton("xmark", help: isSkill ? "Delete skill" : "Delete prompt") {
                    appState.deleteItem(id: item.id)
                }
            }
            .padding(6)
            .transition(.opacity)
        }
    }

    private func editSkill() {
        if case .skill(let skill) = item { appState.beginEditingSkill(skill) }
    }

    private func convertPrompt() {
        if case .prompt(let prompt) = item { appState.beginConverting(prompt) }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var copiedBadge: some View {
        if justCopied {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Copied")
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.78)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    private func openDetail() {
        appState.expand(item)
    }

    private func beginEditOrExpand() {
        if case .prompt(let prompt) = item {
            appState.beginEditing(prompt)
        } else {
            appState.expand(item)
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
