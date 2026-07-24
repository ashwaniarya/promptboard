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
        let document = Frontmatter.parse(export.skillMarkdown)
        #expect(document.fields["name"] == "code-review")
        #expect(document.fields["description"] == "Code Review. Saved PromptBoard prompt, user-invoked only.")
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

    @Test func descriptionIsNeverEmpty() throws {
        let export = SkillExportRenderer.render(prompt(title: "   "))
        let document = Frontmatter.parse(export.skillMarkdown)
        let description = try #require(document.fields["description"])
        #expect(!description.isEmpty)
        #expect(description.hasPrefix("Untitled"))
    }

    @Test func nameIsCappedAtCodexLimit() {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "word ", count: 40)))
        #expect(export.folderName.count <= 64)
        #expect(!export.folderName.hasSuffix("-"))
    }

    @Test func descriptionIsCappedAtCodexLimit() throws {
        let export = SkillExportRenderer.render(prompt(title: String(repeating: "x", count: 2000)))
        let document = Frontmatter.parse(export.skillMarkdown)
        let description = try #require(document.fields["description"])
        #expect(description.count <= 1024)
    }

    @Test func openAIPolicyDisablesImplicitInvocation() {
        let export = SkillExportRenderer.render(prompt(title: "Code Review"))
        #expect(export.openAIPolicy.contains("allow_implicit_invocation: false"))
    }
}
