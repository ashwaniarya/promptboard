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

            HStack(spacing: 0) {
                GroupSidebarView(appState: appState)
                    .frame(width: 200)
                VStack(spacing: 22) {
                    searchBar
                    LibraryGridView(appState: appState)
                }
                .padding(.top, 56)
                .padding(.trailing, 8)
            }

            if let chainEditorMode = appState.chainEditorMode {
                chainEditorLayer(chainEditorMode)
            } else if let skillEditorMode = appState.skillEditorMode {
                skillEditorLayer(skillEditorMode)
            } else if let editorMode = appState.editorMode {
                editorLayer(editorMode)
            } else if let expandedItem = appState.expandedItem {
                detailLayer(expandedItem)
            }

            if let convertingPrompt = appState.convertingPrompt {
                convertLayer(convertingPrompt)
            }

            if let adoptingItem = appState.adoptingItem {
                adoptLayer(adoptingItem)
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
            .frame(height: Constants.toolbarControlHeight)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
            .frame(maxWidth: .infinity)

            trailingControls
        }
        .padding(.horizontal, Constants.boardHorizontalPadding)
    }

    // The + menu and column toggle share one hit-testing surface that absorbs stray
    // taps: without it, a near-miss on the small toggle falls through to the
    // full-screen background gesture below and dismisses the overlay. The buttons
    // keep working — a simultaneous gesture lets their taps through unaffected.
    private var trailingControls: some View {
        HStack(spacing: 12) {
            newMenu
            columnToggle
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
    }

    private var newMenu: some View {
        Menu {
            Button("New skill") { appState.beginCreatingSkill() }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(width: Constants.toolbarControlHeight, height: Constants.toolbarControlHeight)
                .background(Circle().fill(.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        } primaryAction: {
            appState.beginCreating()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New (⌘N for prompt)")
        .background(
            Button("") { appState.beginCreating() }
                .keyboardShortcut("n", modifiers: .command)
                .hidden()
        )
    }

    private var columnToggle: some View {
        HStack(spacing: 0) {
            ForEach([2, 3, 4], id: \.self) { count in
                Button { appState.columnCount = count } label: {
                    Image(systemName: columnIcon(count))
                        .font(.system(size: 13))
                        .foregroundStyle(appState.columnCount == count ? .primary : .secondary)
                        .frame(width: 32, height: Constants.toolbarControlHeight)
                        .background(appState.columnCount == count ? Color.white.opacity(0.14) : .clear)
                }
                .buttonStyle(.plain)
                .help("\(count) columns")
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
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

    private func convertLayer(_ prompt: Prompt) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.convertingPrompt = nil }

            ConvertPromptSheet(prompt: prompt, appState: appState)
                .id(prompt.id)
        }
        .transition(.opacity)
    }

    private func adoptLayer(_ item: ExternalItem) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.adoptingItem = nil }

            AdoptExternalSheet(
                item: item,
                onAdopt: { appState.confirmAdopt(mode: $0) },
                onCancel: { appState.adoptingItem = nil }
            )
            .id(item.id)
        }
        .transition(.opacity)
    }

    private func chainEditorLayer(_ mode: AppState.ChainEditorMode) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.chainEditorMode = nil }

            ChainEditorView(mode: mode, appState: appState)
                .id(ChainEditorView.identity(mode))
        }
        .transition(.opacity)
    }

    private func skillEditorLayer(_ mode: AppState.SkillEditorMode) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.skillEditorMode = nil }

            SkillEditorView(mode: mode, appState: appState)
                .id(appState.skillEditorIdentity)
        }
        .transition(.opacity)
    }

    private func detailLayer(_ item: LibraryEntry) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .contentShape(Rectangle())
                .onTapGesture { appState.expandedItem = nil }

            ItemDetailView(item: item, appState: appState)
                .id(item.id)
        }
        .transition(.opacity)
    }
}
