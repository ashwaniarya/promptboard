import AppKit
import SwiftUI
import PromptBoardKit

// The editable twin of ItemDetailView (Option A): metadata header, a file rail with
// add/import/rename/delete, and a text editor for the selected file. Metadata + file
// text commit on Save; structural file ops apply immediately.
struct SkillEditorView: View {
    let mode: AppState.SkillEditorMode
    let appState: AppState

    @State private var name: String
    @State private var descriptionText: String
    @State private var group: String
    @State private var bodyText: String
    @State private var selectedFile: String?
    @State private var fileBuffers: [String: String] = [:]
    @State private var binaryFiles: Set<String> = []
    @State private var isAddingFile = false
    @State private var newFilePath = ""
    @State private var renamingPath: String?
    @State private var renameText = ""

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    init(mode: AppState.SkillEditorMode, appState: AppState) {
        self.mode = mode
        self.appState = appState
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _descriptionText = State(initialValue: "")
            _group = State(initialValue: "")
            _bodyText = State(initialValue: "")
        case .edit(let skill):
            _name = State(initialValue: skill.name)
            _descriptionText = State(initialValue: skill.description)
            _group = State(initialValue: skill.group ?? "")
            _bodyText = State(initialValue: skill.body)
        }
    }

    private var skillID: UUID? { if case .edit(let skill) = mode { skill.id } else { nil } }
    private var canManageFiles: Bool { skillID != nil }
    private var isCreate: Bool { if case .create = mode { true } else { false } }
    private var liveFiles: [SkillFile] {
        guard let skillID else { return [] }
        for case .skill(let skill) in appState.store.items where skill.id == skillID { return skill.files }
        return []
    }
    private var isSaveDisabled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                fileRail
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                editorPane
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            footer
        }
        .frame(width: 780, height: 560)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        .onExitCommand { appState.skillEditorMode = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(accent)
                TextField("skill-name", text: $name)
                    .textFieldStyle(.plain).font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Text(isCreate ? "new skill" : "editing")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            TextField("What this skill does (one line)", text: $descriptionText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.82))
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("group (optional)", text: $group)
                    .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: 220)
            }
        }
        .padding(16)
    }

    private var fileRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FILES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 12).padding(.vertical, 8)
            fileRow(rowName: "SKILL.md", path: nil, systemImage: "doc.text.fill")
            ForEach(liveFiles, id: \.relativePath) { file in
                fileRow(rowName: file.relativePath, path: file.relativePath, systemImage: "doc")
            }
            if canManageFiles {
                if isAddingFile { addFileField } else { addImportButtons }
            } else {
                Text("Save the skill to add files")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 14).padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 220).frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func fileRow(rowName: String, path: String?, systemImage: String) -> some View {
        if let path, renamingPath == path {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11)).frame(width: 15).foregroundStyle(accent)
                TextField("", text: $renameText).textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced)).onSubmit { commitRename(from: path) }
            }
            .padding(.horizontal, 15).padding(.vertical, 6)
        } else {
            let selected = selectedFile == path
            HStack(spacing: 6) {
                Button { selectFile(path) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: systemImage).font(.system(size: 11)).frame(width: 15)
                            .foregroundStyle(selected ? accent : .secondary)
                        Text(rowName)
                            .font(.system(size: 12, design: rowName.hasSuffix(".md") ? .default : .monospaced))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let path, canManageFiles {
                    Menu {
                        Button("Rename…") { beginRename(path) }
                        Button("Delete", role: .destructive) { deleteFile(path) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .menuStyle(.borderlessButton).frame(width: 16)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? accent.opacity(0.16) : .clear))
            .padding(.horizontal, 6)
        }
    }

    private var addImportButtons: some View {
        HStack(spacing: 12) {
            Button { isAddingFile = true; newFilePath = "" } label: {
                Label("New", systemImage: "plus").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(accent)
            Button { importFile() } label: {
                Label("Import", systemImage: "square.and.arrow.down").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundStyle(accent)
        }
        .padding(.horizontal, 15).padding(.top, 8)
    }

    private var addFileField: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.badge.plus").font(.system(size: 11)).foregroundStyle(accent)
            TextField("reference.md", text: $newFilePath)
                .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                .onSubmit(commitNewFile)
        }
        .padding(.horizontal, 15).padding(.vertical, 6)
    }

    @ViewBuilder
    private var editorPane: some View {
        if selectedFile == nil {
            TextEditor(text: $bodyText)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let path = selectedFile, binaryFiles.contains(path) {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape").font(.system(size: 28)).foregroundStyle(.tertiary)
                Text("Binary file — rename or delete only").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let path = selectedFile {
            TextEditor(text: bindingForFile(path))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            if case .edit(let skill) = mode {
                Button(role: .destructive) {
                    appState.deleteItem(id: skill.id)
                    appState.skillEditorMode = nil
                } label: { Label("Delete skill", systemImage: "trash") }
                .buttonStyle(.plain).foregroundStyle(.red.opacity(0.9))
            }
            Spacer()
            Button("Cancel") { appState.skillEditorMode = nil }.buttonStyle(.plain)
            Button(isCreate ? "Create" : "Save") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isSaveDisabled)
        }
        .padding(16)
    }

    private func bindingForFile(_ path: String) -> Binding<String> {
        Binding(get: { fileBuffers[path] ?? "" }, set: { fileBuffers[path] = $0 })
    }

    private func selectFile(_ path: String?) {
        selectedFile = path
        guard let path, let skillID, fileBuffers[path] == nil, !binaryFiles.contains(path) else { return }
        if let text = appState.store.skillFileText(id: skillID, relativePath: path) {
            fileBuffers[path] = text
        } else {
            binaryFiles.insert(path)
        }
    }

    private func commitNewFile() {
        guard let skillID else { return }
        let path = newFilePath.trimmingCharacters(in: .whitespaces)
        isAddingFile = false
        newFilePath = ""
        guard !path.isEmpty else { return }
        if appState.store.writeSkillFile(id: skillID, relativePath: path, data: Data()) != nil {
            fileBuffers[path] = ""
            selectedFile = path
        }
    }

    private func beginRename(_ path: String) {
        renamingPath = path
        renameText = path
    }

    private func commitRename(from oldPath: String) {
        guard let skillID else { renamingPath = nil; return }
        let newPath = renameText.trimmingCharacters(in: .whitespaces)
        renamingPath = nil
        guard !newPath.isEmpty, newPath != oldPath else { return }
        guard appState.store.renameSkillFile(id: skillID, from: oldPath, to: newPath) != nil else { return }
        if let buffer = fileBuffers[oldPath] { fileBuffers[newPath] = buffer }
        fileBuffers[oldPath] = nil
        if binaryFiles.remove(oldPath) != nil { binaryFiles.insert(newPath) }
        if selectedFile == oldPath { selectedFile = newPath }
    }

    private func deleteFile(_ path: String) {
        guard let skillID else { return }
        _ = appState.store.deleteSkillFile(id: skillID, relativePath: path)
        fileBuffers[path] = nil
        binaryFiles.remove(path)
        if selectedFile == path { selectedFile = nil }
    }

    private func importFile() {
        guard let skillID else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let existing = Set(liveFiles.map(\.relativePath))
        var candidate = url.lastPathComponent
        if existing.contains(candidate) {
            let stem = (candidate as NSString).deletingPathExtension
            let ext = (candidate as NSString).pathExtension
            func compose(_ i: Int) -> String { ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)" }
            var n = 2
            while existing.contains(compose(n)) { n += 1 }
            candidate = compose(n)
        }
        _ = appState.store.writeSkillFile(id: skillID, relativePath: candidate, data: data)
    }

    private func save() {
        let trimmedGroup = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupValue = trimmedGroup.isEmpty ? nil : trimmedGroup
        switch mode {
        case .create:
            appState.saveNewSkill(name: name, description: descriptionText, group: groupValue, body: bodyText)
        case .edit(let skill):
            for (path, text) in fileBuffers where !binaryFiles.contains(path) {
                _ = appState.store.writeSkillFile(id: skill.id, relativePath: path, data: Data(text.utf8))
            }
            _ = appState.store.updateSkill(id: skill.id, name: name, description: descriptionText, group: groupValue, body: bodyText)
            appState.skillEditorMode = nil
        }
    }
}
