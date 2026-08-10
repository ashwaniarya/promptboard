import SwiftUI
import PromptBoardKit

struct GroupSidebarView: View {
    @Bindable var appState: AppState
    @State private var expanded: Set<String> = []
    @State private var addingFolder = false
    @State private var newFolderName = ""
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    // A folder node paired with its indentation depth. Flattening the tree into a
    // single list (instead of a recursive view builder) sidesteps SwiftUI's
    // "opaque return type defined in terms of itself" limit on self-referential views.
    private struct FolderRow: Identifiable {
        let node: FolderNode
        let depth: Int
        var id: String { node.path }
    }

    private func visibleRows(_ nodes: [FolderNode], depth: Int) -> [FolderRow] {
        nodes.flatMap { node -> [FolderRow] in
            var rows = [FolderRow(node: node, depth: depth)]
            if expanded.contains(node.path) {
                rows += visibleRows(node.children, depth: depth + 1)
            }
            return rows
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("GROUPS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button { addingFolder = true; appState.requestFocusNewFolder() } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("New folder")
            }
            .padding(.horizontal, 12).padding(.bottom, 6)

            allRow
            ForEach(visibleRows(appState.folderTree, depth: 0)) { row in
                folderRow(row.node, depth: row.depth)
            }
            if addingFolder { newFolderField }

            Spacer(minLength: 0)

            Toggle("Show external", isOn: $appState.showExternalItems)
                .toggleStyle(.switch).controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.horizontal, 11).padding(.bottom, 12)
        }
        .padding(.top, 64).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.18))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
        .onChange(of: appState.overlaySession) {
            addingFolder = false
            newFolderName = ""
        }
    }

    private var allRow: some View {
        rowButton(title: "All", systemImage: "square.stack.3d.up.fill",
                  folder: nil, count: appState.store.items.count, depth: 0, hasChildren: false)
            .dropDestination(for: String.self) { ids, _ in
                for id in ids.compactMap(UUID.init) { appState.moveItem(id: id, toFolder: nil) }
                return !ids.isEmpty
            }
    }

    private func folderRow(_ node: FolderNode, depth: Int) -> some View {
        rowButton(title: node.name, systemImage: "folder.fill",
                  folder: node.path, count: node.subtreeCount, depth: depth,
                  hasChildren: !node.children.isEmpty)
            .dropDestination(for: String.self) { ids, _ in
                for id in ids.compactMap(UUID.init) { appState.moveItem(id: id, toFolder: node.path) }
                return !ids.isEmpty
            }
    }

    private func rowButton(title: String, systemImage: String, folder: String?, count: Int, depth: Int, hasChildren: Bool) -> some View {
        let selected = appState.selectedFolder == folder
        return Button {
            appState.selectedFolder = folder
        } label: {
            HStack(spacing: 6) {
                if hasChildren {
                    Button {
                        if expanded.contains(folder ?? "") { expanded.remove(folder ?? "") }
                        else { expanded.insert(folder ?? "") }
                    } label: {
                        Image(systemName: expanded.contains(folder ?? "") ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9)).frame(width: 10)
                    }.buttonStyle(.plain)
                } else {
                    // Reserve the chevron's exact slot (hidden), so childless rows align
                    // with expandable ones. A bare Color.clear is height-greedy and would
                    // stretch the row to fill the sidebar.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9)).frame(width: 10).hidden()
                }
                Image(systemName: systemImage).font(.system(size: 11)).frame(width: 16)
                Text(title).font(.system(size: 12.5)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10.5))
                    .foregroundStyle(selected ? accent.opacity(0.9) : .white.opacity(0.4))
            }
            .padding(.leading, CGFloat(depth) * 12)
            .foregroundStyle(selected ? .white : .white.opacity(0.66))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var newFolderField: some View {
        TextField(Constants.newFolderPlaceholder, text: $newFolderName)
            .textFieldStyle(.plain).font(.system(size: 12))
            .padding(.horizontal, 11).padding(.vertical, 4)
            .onSubmit {
                appState.createFolder(named: newFolderName, under: appState.selectedFolder)
                newFolderName = ""; addingFolder = false
            }
            .onExitCommand { newFolderName = ""; addingFolder = false }
    }
}
