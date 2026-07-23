import SwiftUI
import PromptBoardKit

struct GroupSidebarView: View {
    let appState: AppState
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("GROUPS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            row(title: "All", systemImage: "square.stack.3d.up.fill", group: nil, count: appState.store.items.count)
            ForEach(appState.groupCounts, id: \.name) { group in
                row(title: group.name, systemImage: "folder.fill", group: group.name, count: group.count)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 64)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        }
    }

    private func row(title: String, systemImage: String, group: String?, count: Int) -> some View {
        let selected = appState.selectedGroup == group
        return Button {
            appState.selectedGroup = group
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(selected ? accent.opacity(0.9) : Color.white.opacity(0.4))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.66))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
