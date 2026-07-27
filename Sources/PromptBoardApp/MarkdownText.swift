import MarkdownUI
import SwiftUI

// App-wide markdown rendering for cards + the detail view. Display-only — the raw
// markdown is what gets copied (see AppState.copyToClipboard). Built on MarkdownUI's
// `basic` theme (its block layout is already MainActor-correct) with inline text
// styles tuned for the dark overlay.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        Markdown(markdown)
            .markdownTheme(.promptBoard)
            .textSelection(.enabled)
    }

    // Card previews are compact and fixed-height, so a full-size `# H1` dominates the
    // card and breaks the grid's visual rhythm. Demote ATX headings to bold text so a
    // preview reads at body weight. The detail view keeps real headings, and the raw
    // markdown (what actually gets copied) is untouched. We avoid MarkdownUI's block
    // heading styles here because their closures build views in a nonisolated context,
    // which Swift 6 strict concurrency rejects.
    static func flattenedForPreview(_ markdown: String) -> String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let stripped = line.drop { $0 == " " }
            let hashes = stripped.prefix { $0 == "#" }
            guard (1...6).contains(hashes.count) else { return String(line) }
            let text = stripped.dropFirst(hashes.count).drop { $0 == " " }
            guard !text.isEmpty else { return String(line) }
            return "**\(text)**"
        }
        .joined(separator: "\n")
    }
}

extension MarkdownUI.Theme {
    static var promptBoard: MarkdownUI.Theme {
        MarkdownUI.Theme.basic
            .text {
                ForegroundColor(Color.white.opacity(0.82))
                FontSize(13)
            }
            .strong { FontWeight(.semibold) }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(11.5)
                ForegroundColor(Color(red: 0.78, green: 0.80, blue: 1.0))
                BackgroundColor(Color.white.opacity(0.10))
            }
            .link {
                ForegroundColor(Color(red: 0.62, green: 0.65, blue: 1.0))
            }
    }
}
