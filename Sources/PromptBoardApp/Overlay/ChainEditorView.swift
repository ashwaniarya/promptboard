import SwiftUI
import PromptBoardKit

struct ChainEditorView: View {
    let mode: AppState.ChainEditorMode
    let appState: AppState

    @State private var title: String
    @State private var steps: [Chain.Step]

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    init(mode: AppState.ChainEditorMode, appState: AppState) {
        self.mode = mode
        self.appState = appState
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _steps = State(initialValue: [])
        case .edit(let chain):
            _title = State(initialValue: chain.title)
            _steps = State(initialValue: chain.steps)
        }
    }

    static func identity(_ mode: AppState.ChainEditorMode) -> String {
        if case .edit(let chain) = mode { chain.id.uuidString } else { "create" }
    }

    private var isCreate: Bool { if case .create = mode { true } else { false } }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || steps.contains { step in
                if case .custom(let text) = step { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } else { false }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.number").foregroundStyle(accent)
                TextField("Chain title", text: $title)
                    .textFieldStyle(.plain).font(.title3.weight(.semibold))
            }
            .padding(16)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(steps.indices, id: \.self) { index in stepRow(index) }
                    if steps.isEmpty {
                        Text("No steps yet").foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                }
                .padding(16)
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            footer
        }
        .frame(width: 640, height: 520)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.45), radius: 40, y: 16)
        .onExitCommand { appState.chainEditorMode = nil }
    }

    private func stepRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            stepContent(index)
            VStack(spacing: 4) {
                Button { moveStep(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                Button { moveStep(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == steps.count - 1)
                Button { steps.remove(at: index) } label: { Image(systemName: "xmark") }
                    .help("Remove step")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func stepContent(_ index: Int) -> some View {
        switch steps[index] {
        case .linked(let promptID):
            if let prompt = appState.store.prompts.first(where: { $0.id == promptID }) {
                Label(prompt.title, systemImage: "link").frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("missing").italic().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .custom:
            TextEditor(text: customTextBinding(index))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(6)
                .frame(minHeight: 60, maxHeight: 140)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.05)))
        }
    }

    private var footer: some View {
        HStack {
            Menu("Add prompt") {
                ForEach(appState.store.prompts) { prompt in
                    Button(prompt.title) { steps.append(.linked(promptID: prompt.id)) }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button("Add custom") { steps.append(.custom(text: "")) }.buttonStyle(.plain)
            if case .edit(let chain) = mode {
                Button(role: .destructive) {
                    appState.deleteItem(id: chain.id)
                    appState.chainEditorMode = nil
                } label: { Label("Delete chain", systemImage: "trash") }
                .buttonStyle(.plain).foregroundStyle(.red.opacity(0.9))
            }
            Spacer()
            if let chainSaveError = appState.chainSaveError {
                Text(chainSaveError).font(.caption).foregroundStyle(.red.opacity(0.9))
            }
            Button("Cancel") { appState.chainEditorMode = nil }.buttonStyle(.plain)
            Button(isCreate ? "Create" : "Save") { appState.saveChain(title: title, steps: steps) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isSaveDisabled)
        }
        .padding(16)
    }

    private func customTextBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard steps.indices.contains(index), case .custom(let text) = steps[index] else { return "" }
                return text
            },
            set: { if steps.indices.contains(index) { steps[index] = .custom(text: $0) } }
        )
    }

    private func moveStep(_ index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }
}
