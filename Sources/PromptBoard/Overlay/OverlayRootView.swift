import SwiftUI
import PromptBoardKit

struct OverlayRootView: View {
    @Bindable var appState: AppState
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .overlay(Color.black.opacity(0.2))
                .contentShape(Rectangle())
                .onTapGesture { appState.handleBackgroundClick() }

            VStack(spacing: 28) {
                searchBar
                MasonryGridView(appState: appState)
            }
            .padding(.top, 64)

            if let editorMode = appState.editorMode {
                editorLayer(editorMode)
            }
        }
        .ignoresSafeArea()
        .defaultFocus($searchFieldFocused, true)
        .onChange(of: appState.overlaySession) {
            searchFieldFocused = true
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search prompts…", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFieldFocused)
                    .onExitCommand { appState.handleEscape() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
            .frame(maxWidth: 560)

            Button {
                appState.beginCreating()
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("New Prompt (⌘N)")
        }
    }

    private func editorLayer(_ editorMode: AppState.EditorMode) -> some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture { appState.editorMode = nil }

            PromptEditorView(
                mode: editorMode,
                onSave: { title, content in
                    appState.saveEditor(title: title, content: content)
                },
                onDelete: {
                    if case .edit(let prompt) = editorMode {
                        return { appState.deletePrompt(id: prompt.id) }
                    }
                    return nil
                }(),
                onCancel: { appState.editorMode = nil }
            )
            .id(editorMode)
        }
        .transition(.opacity)
    }
}
