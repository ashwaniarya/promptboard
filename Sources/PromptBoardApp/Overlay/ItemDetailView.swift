import AppKit
import SwiftUI
import PromptBoardKit

// Read-only expanded view. A prompt shows its full rendered markdown; a skill shows
// a file tree beside the rendered SKILL.md (select a file to view it). Editing is Layer C.
struct ItemDetailView: View {
    let item: LibraryEntry
    let appState: AppState

    @State private var selectedFile: String?
    @State private var justCopied = false

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)
    private var isSkill: Bool { item.kind == .skill }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            bodyContent
        }
        .frame(width: 760, height: 520)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        .onExitCommand { appState.expandedItem = nil }
    }

    private var header: some View {
        HStack(spacing: 9) {
            if isSkill {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(accent)
            }
            Text(item.title).font(.title3.weight(.semibold)).lineLimit(1)
            if isSkill {
                Text("skill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.16)))
            }
            if let group = item.group {
                Text(group)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.07)))
            }
            Spacer(minLength: 8)
            copyButton
            closeButton
        }
        .padding(16)
    }

    private var copyButton: some View {
        Button(action: copyCurrent) {
            Label(justCopied ? "Copied" : "Copy markdown", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(justCopied ? Color.green : accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(justCopied ? Color.green.opacity(0.14) : accent.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button { appState.expandedItem = nil } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch item {
        case .prompt(let prompt):
            ScrollView {
                MarkdownText(markdown: prompt.content)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .skill(let skill):
            HStack(spacing: 0) {
                fileTree(skill)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                ScrollView {
                    renderedFile(skill)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func fileTree(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FILES")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 8)
            fileRow(name: "SKILL.md", path: nil, systemImage: "doc.text.fill")
            ForEach(skill.files, id: \.relativePath) { file in
                fileRow(name: file.relativePath, path: file.relativePath, systemImage: "doc")
            }
            Spacer(minLength: 0)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func fileRow(name: String, path: String?, systemImage: String) -> some View {
        let selected = selectedFile == path
        return Button {
            selectedFile = path
            justCopied = false
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11)).frame(width: 15)
                    .foregroundStyle(selected ? accent : .secondary)
                Text(name)
                    .font(.system(size: 12, design: name.hasSuffix(".md") ? .default : .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? accent.opacity(0.16) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func renderedFile(_ skill: Skill) -> some View {
        let text = currentSkillText(skill)
        if selectedFile == nil || selectedFile?.hasSuffix(".md") == true {
            MarkdownText(markdown: text)
        } else {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
        }
    }

    private func currentSkillText(_ skill: Skill) -> String {
        guard let selectedFile else { return skill.body }
        return appState.store.skillFileText(id: skill.id, relativePath: selectedFile) ?? "(unreadable)"
    }

    private func copyCurrent() {
        let text: String
        switch item {
        case .prompt(let prompt): text = prompt.content
        case .skill(let skill): text = currentSkillText(skill)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation { justCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { justCopied = false }
        }
    }
}
