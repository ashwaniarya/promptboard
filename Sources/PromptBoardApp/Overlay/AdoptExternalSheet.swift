import PromptBoardKit
import SwiftUI

struct AdoptExternalSheet: View {
    let item: ExternalItem
    let onAdopt: (LibraryRepository.AdoptMode) -> Void
    let onCancel: () -> Void

    private let accent = Color(red: 0.49, green: 0.51, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(accent)
                Text("Adopt “\(item.name)”").font(.title3.weight(.semibold))
            }
            Text("From \(item.origin) · \(item.url.path)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)

            VStack(alignment: .leading, spacing: 12) {
                choice(
                    title: "Move into library", mode: .move,
                    detail: "Backs up the original, replaces it with a link, and syncs to every tool."
                )
                choice(
                    title: "Copy into library", mode: .copy,
                    detail: "Leaves the original untouched. The two copies can drift apart."
                )
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 36, y: 12)
        .onExitCommand(perform: onCancel)
    }

    private func choice(title: String, mode: LibraryRepository.AdoptMode, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(title) { onAdopt(mode) }
                .buttonStyle(.borderedProminent)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
