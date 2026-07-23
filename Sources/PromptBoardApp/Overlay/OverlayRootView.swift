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
                LibraryGridView(appState: appState)
            }
            .padding(.top, 64)

            if let editorMode = appState.editorMode {
                editorLayer(editorMode)
            }
        }
        .ignoresSafeArea()
        .defaultFocus($searchFieldFocused, true)
        .onChange(of: appState.overlaySession) {
            if appState.editorMode == nil {
                searchFieldFocused = true
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(Constants.searchFieldPlaceholder, text: $appState.searchText)
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

            columnToggle
        }
    }

    private var columnToggle: some View {
        HStack(spacing: 0) {
            ForEach([2, 3, 4], id: \.self) { count in
                Button { appState.columnCount = count } label: {
                    Image(systemName: columnIcon(count))
                        .font(.system(size: 13))
                        .foregroundStyle(appState.columnCount == count ? .primary : .secondary)
                        .frame(width: 32, height: 34)
                        .background(appState.columnCount == count ? Color.white.opacity(0.14) : .clear)
                }
                .buttonStyle(.plain)
                .help("\(count) columns")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
    }

    private func columnIcon(_ count: Int) -> String {
        switch count {
        case 2: "square.grid.2x2"
        case 4: "square.grid.4x3.fill"
        default: "square.grid.3x2"
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
                        return { appState.deleteItem(id: prompt.id) }
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
