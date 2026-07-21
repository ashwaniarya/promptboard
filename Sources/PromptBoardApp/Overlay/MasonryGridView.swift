import SwiftUI
import PromptBoardKit

struct MasonryGridView: View {
    let appState: AppState

    private let horizontalPadding = 48.0
    private let columnSpacing = 16.0

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - horizontalPadding * 2
            let columnCount = max(2, min(5, Int(availableWidth / 320)))
            let cardWidth = (availableWidth - columnSpacing * Double(columnCount - 1)) / Double(columnCount)
            let columns = MasonryLayout.distribute(appState.visibleItems, columns: columnCount) {
                MasonryLayout.estimatedCardHeight(title: $0.title, content: $0.previewText, cardWidth: cardWidth)
            }

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if appState.visibleItems.isEmpty {
                        emptyState
                    } else {
                        HStack(alignment: .top, spacing: columnSpacing) {
                            ForEach(columns.indices, id: \.self) { columnIndex in
                                VStack(spacing: columnSpacing) {
                                    ForEach(columns[columnIndex]) { item in
                                        PromptCardView(item: item, appState: appState)
                                    }
                                }
                                .frame(width: cardWidth)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 48)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { appState.handleBackgroundClick() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: appState.searchText.isEmpty ? "square.grid.2x2" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(
                appState.searchText.isEmpty
                    ? "No prompts yet — press ⌘N or + to add one"
                    : "No prompts match “\(appState.searchText)”"
            )
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 120)
    }
}
