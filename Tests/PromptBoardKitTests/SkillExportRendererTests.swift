import Foundation
import Testing
@testable import PromptBoardKit

struct SkillExportRendererTests {
    private func prompt(title: String, content: String = "Body text.") -> Prompt {
        Prompt(title: title, content: content)
    }

    @Test func folderNameIsTheTitleSlug() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.folderName == "code-review")
    }

    @Test func emitsNameDescriptionAndInvocationOptOut() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.skillMarkdown.contains("name: \"code-review\"\n"))
        #expect(export.skillMarkdown.contains("description: \"Code Review. Saved PromptBoard prompt, user-invoked only.\"\n"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["disable-model-invocation"] == "true")
    }

    @Test func bodyIsCopiedVerbatimWithoutPromptBoardFrontmatter() {
        let export = SkillExportRenderer.render(prompt(title: "Explain", content: "Line one\n\nLine two"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.body == "Line one\n\nLine two")
        #expect(!export.skillMarkdown.contains("createdAt"))
        #expect(!export.skillMarkdown.contains("updatedAt"))
    }

    @Test func descriptionWithColonIsQuotedSoYamlStaysValid() {
        let export = SkillExportRenderer.render(prompt(title: "Ratio: 2:1"))
        #expect(export.skillMarkdown.contains("description: \"Ratio: 2:1. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func descriptionIsNeverEmpty() {
        let export = SkillExportRenderer.render(prompt(title: "   "))
        #expect(export.skillMarkdown.contains("description: \"Untitled. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func nameIsCappedAtCodexLimit() {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "word ", count: 40)))
        #expect(export.folderName.count <= 64)
        #expect(!export.folderName.hasSuffix("-"))
    }

    @Test func descriptionIsCappedAtCodexLimit() throws {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "x", count: 2000)))
        let line = try #require(export.skillMarkdown.split(separator: "\n").first { $0.hasPrefix("description: ") })
        let quoted = line.dropFirst("description: ".count)
        #expect(quoted.hasPrefix("\""))
        #expect(quoted.hasSuffix("\""))
        #expect(quoted.dropFirst().dropLast().count <= 1024)
    }

    @Test func openAIPolicyDisablesImplicitInvocation() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.openAIPolicy.contains("allow_implicit_invocation: false"))
    }

    @Test func leadingBracketNoLongerBreaksYAML() {
        let export = SkillExportRenderer.render(prompt(title: "[Draft] Blog Post"))
        #expect(export.skillMarkdown.contains("description: \"[Draft] Blog Post. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func leadingAndEmbeddedQuotesAreEscaped() {
        let export = SkillExportRenderer.render(prompt(title: "\"Explain Like I'm Five\" Rewrite"))
        #expect(export.skillMarkdown.contains("description: \"\\\"Explain Like I'm Five\\\" Rewrite. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func nameThatWouldParseAsYAMLBooleanStaysQuotedString() {
        let export = SkillExportRenderer.render(prompt(title: "No"))
        #expect(export.folderName == "no")
        #expect(export.skillMarkdown.contains("name: \"no\""))
    }

    @Test func descriptionWithColonAndQuoteEscapesBoth() {
        let export = SkillExportRenderer.render(prompt(title: "Say \"hello\": now"))
        #expect(export.skillMarkdown.contains("description: \"Say \\\"hello\\\": now. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func carriageReturnInTitleIsFlattenedToSpace() {
        let export = SkillExportRenderer.render(prompt(title: "Line1\rLine2"))
        #expect(export.skillMarkdown.contains("description: \"Line1 Line2. Saved PromptBoard prompt, user-invoked only.\""))
    }

    @Test func escapeCharacterInTitleIsStrippedFromOutput() throws {
        let export = SkillExportRenderer.render(prompt(title: "Broken \u{1B}[31mRed\u{1B}[0m Text"))
        let descriptionLine = try #require(export.skillMarkdown.split(separator: "\n").first { $0.hasPrefix("description: ") })
        #expect(!descriptionLine.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["disable-model-invocation"] == "true")
    }
}
