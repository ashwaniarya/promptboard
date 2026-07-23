import SwiftUI
import PromptBoardKit

struct LibraryGridView: View {
    let appState: AppState

    private let horizontalPadding = 40.0
    private let spacing = 16.0

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { appState.handleBackgroundClick() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.visibleItems.isEmpty {
            emptyState.padding(.top, 120)
        } else {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                    count: appState.columnCount
                ),
                spacing: spacing
            ) {
                ForEach(appState.visibleItems) { item in
                    PromptCardView(item: item, appState: appState)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 44)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: appState.searchText.isEmpty ? "square.grid.2x2" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(
                appState.searchText.isEmpty
                    ? "Nothing here yet — press ⌘N to add a prompt"
                    : "No matches for “\(appState.searchText)”"
            )
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }
}
