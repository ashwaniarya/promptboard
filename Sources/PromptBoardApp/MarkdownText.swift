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
