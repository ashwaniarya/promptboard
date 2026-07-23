import SwiftUI
import PromptBoardKit

// Small sheet to turn a prompt into a skill: prefilled name/group, a required
// one-line description, and a keep-original toggle (default off = a true convert).
struct ConvertPromptSheet: View {
    let prompt: Prompt
    let appState: AppState

    @State private var name: String
    @State private var descriptionText = ""
    @State private var group: String
    @State private var keepOriginal = false

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    init(prompt: Prompt, appState: AppState) {
        self.prompt = prompt
        self.appState = appState
        _name = State(initialValue: prompt.title)
        _group = State(initialValue: prompt.group ?? "")
    }

    private var isDisabled: Bool {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill").foregroundStyle(accent)
                Text("Convert to skill").font(.title3.weight(.semibold))
            }
            TextField("skill-name", text: $name)
                .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
            Divider()
            TextField("What this skill does (one line)", text: $descriptionText)
                .textFieldStyle(.plain).font(.system(size: 12))
            TextField("group (optional)", text: $group)
                .textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("Keep the original prompt", isOn: $keepOriginal)
                .toggleStyle(.checkbox).font(.system(size: 12))
            HStack {
                Spacer()
                Button("Cancel") { appState.convertingPrompt = nil }.buttonStyle(.plain)
                Button("Convert") {
                    let trimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.confirmConvert(
                        prompt: prompt, name: name, description: descriptionText,
                        group: trimmed.isEmpty ? nil : trimmed, keepOriginal: keepOriginal
                    )
                }
                .buttonStyle(.borderedProminent).disabled(isDisabled)
            }
        }
        .padding(24).frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 36, y: 12)
        .onExitCommand { appState.convertingPrompt = nil }
    }
}
