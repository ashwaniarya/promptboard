import SwiftUI
import PromptBoardKit

struct PromptEditorView: View {
    let mode: AppState.EditorMode
    let onSave: (String, String) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var title: String
    @State private var content: String
    @FocusState private var titleFocused: Bool

    init(
        mode: AppState.EditorMode,
        onSave: @escaping (String, String) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        switch mode {
        case .new:
            _title = State(initialValue: "")
            _content = State(initialValue: "")
        case .edit(let prompt):
            _title = State(initialValue: prompt.title)
            _content = State(initialValue: prompt.content)
        }
    }

    private var isContentEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Prompt title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($titleFocused)

            Divider()

            TextEditor(text: $content)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 220, maxHeight: 360)

            HStack {
                if let onDelete {
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.9))
                }

                Spacer()

                Button("Cancel", action: onCancel)

                Button(mode == .new ? "Add Prompt" : "Save") {
                    onSave(title, content)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isContentEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 36, y: 12)
        .onExitCommand { onCancel() }
        .onAppear { titleFocused = true }
    }
}
