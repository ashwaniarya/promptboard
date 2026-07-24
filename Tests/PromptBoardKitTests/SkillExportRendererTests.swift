import Foundation
import Testing
@testable import PromptBoardKit

struct SkillExportRendererTests {
    private let descriptionSuffix = ". Saved PromptBoard prompt, user-invoked only."

    private func prompt(title: String, content: String = "Body text.") -> Prompt {
        Prompt(title: title, content: content)
    }

    private func expectedDescription(_ content: String) -> String {
        "\(content)\(descriptionSuffix)"
    }

    @Test func folderNameIsTheTitleSlug() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.folderName == "code-review")
    }

    @Test func emitsNameDescriptionAndInvocationOptOut() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["name"] == "\"code-review\"")
        #expect(document.fields["description"] == "\"\(expectedDescription("Code Review"))\"")
        #expect(document.fields["disable-model-invocation"] == "true")
    }

    @Test func bodyIsCopiedVerbatimWithoutPromptBoardFrontmatter() {
        let export = SkillExportRenderer.render(prompt(title: "Explain", content: "Line one\n\nLine two"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.body == "Line one\n\nLine two")
        #expect(!export.skillMarkdown.contains("createdAt"))
        #expect(!export.skillMarkdown.contains("updatedAt"))
    }

    @Test func descriptionIsNeverEmpty() {
        let export = SkillExportRenderer.render(prompt(title: "   "))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Untitled"))\"")
    }

    @Test func nameIsCappedAtCodexLimit() {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "abc ", count: 20)))
        #expect(export.folderName.count <= 64)
        #expect(!export.folderName.hasSuffix("-"))
    }

    @Test func descriptionIsCappedAtCodexLimit() throws {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "x", count: 2000)))
        let document = Frontmatter.parse(export.skillMarkdown)
        let quotedDescription = try #require(document.fields["description"])
        let content = quotedDescription.dropFirst().dropLast()
        #expect(content.count <= 1024)
        #expect(content.hasSuffix(descriptionSuffix))
    }

    @Test func openAIPolicyDisablesImplicitInvocation() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.openAIPolicy.contains("allow_implicit_invocation: false"))
    }

    @Test func leadingBracketInTitleIsQuoted() {
        let export = SkillExportRenderer.render(prompt(title: "[Draft] Blog Post"))
        #expect(export.skillMarkdown.contains("description: \"\(expectedDescription("[Draft] Blog Post"))\""))
    }

    @Test func leadingAndEmbeddedQuotesAreEscaped() {
        let export = SkillExportRenderer.render(prompt(title: "\"Explain Like I'm Five\" Rewrite"))
        #expect(export.skillMarkdown.contains("description: \"\\\"Explain Like I'm Five\\\" Rewrite\(descriptionSuffix)\""))
    }

    @Test func nameThatWouldParseAsYAMLBooleanStaysQuotedString() {
        let export = SkillExportRenderer.render(prompt(title: "No"))
        #expect(export.folderName == "no")
        #expect(export.skillMarkdown.contains("name: \"no\""))
    }

    @Test func descriptionWithColonAndQuoteEscapesBoth() {
        let export = SkillExportRenderer.render(prompt(title: "Say \"hello\": now"))
        #expect(export.skillMarkdown.contains("description: \"Say \\\"hello\\\": now\(descriptionSuffix)\""))
    }

    @Test func carriageReturnInTitleIsFlattenedToSpace() {
        let export = SkillExportRenderer.render(prompt(title: "Line1\rLine2"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Line1 Line2"))\"")
    }

    @Test func newlineInTitleIsFlattenedToSpace() {
        let export = SkillExportRenderer.render(prompt(title: "Line1\nLine2"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Line1 Line2"))\"")
    }

    @Test func crlfInTitleCollapsesToASingleSpace() {
        let export = SkillExportRenderer.render(prompt(title: "Line1\r\nLine2"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Line1 Line2"))\"")
    }

    @Test func lineSeparatorInTitleIsFlattenedToSpace() {
        let export = SkillExportRenderer.render(prompt(title: "Line1\u{2028}Line2"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Line1 Line2"))\"")
    }

    @Test func escapeCharacterInTitleIsReplacedWithSpace() {
        let export = SkillExportRenderer.render(prompt(title: "Red\u{1B}[31mText"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Red [31mText"))\"")
    }

    @Test func emojiWithZeroWidthJoinersSurvivesIntact() {
        let export = SkillExportRenderer.render(prompt(title: "Family 👨‍👩‍👧 Planner"))
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["description"] == "\"\(expectedDescription("Family 👨‍👩‍👧 Planner"))\"")
    }
}
