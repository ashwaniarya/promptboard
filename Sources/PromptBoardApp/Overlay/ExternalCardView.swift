import PromptBoardKit
import SwiftUI

// External items live in another tool's directory, so the card is read-only: no
// edit/convert/delete/copy is exposed. The sole action is Adopt, which brings a
// move-or-copy of the item into the library before it can be edited or synced.
struct ExternalCardView: View {
    let item: ExternalItem
    let appState: AppState

    @State private var isHovering = false

    private let cardHeight: CGFloat = 168
    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    private var isSkill: Bool { item.kind == .skill }

    private var conflict: LibraryRepository.SyncConflict? {
        let slug = Slug.make(from: item.name)
        return appState.store.syncConflicts.first { $0.name == slug }
    }

    var body: some View {
        card
            .opacity(0.72)
            .overlay(alignment: .bottomLeading) { conflictBadge }
            .overlay(alignment: .topTrailing) { hoverActions }
            .contentShape(Rectangle())
            .onTapGesture { appState.beginAdopting(item) }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            // Same content-forward layout as a prompt card: a body preview on top, a
            // muted footer below. The body is the item's description (falling back to
            // its path so the card is never empty); the footer keeps the location.
            Text(item.description.isEmpty ? item.url.path : item.description)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 6) {
                Text(item.url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text("Read-only · adopt to edit")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(height: cardHeight, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isHovering ? 0.09 : 0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(isHovering ? 0.20 : 0.09))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isSkill ? "puzzlepiece.extension.fill" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(item.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(item.origin)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.10)))
        }
    }

    @ViewBuilder
    private var conflictBadge: some View {
        if let conflict {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Name conflict")
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.yellow.opacity(0.9)))
            .padding(10)
            .help(conflict.reason)
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        if isHovering {
            Button { appState.beginAdopting(item) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Adopt")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .padding(8)
            .transition(.opacity)
            .help("Adopt into library")
        }
    }
}
