import Testing
@testable import PromptBoardKit

struct FrontmatterTests {
    @Test func parsesFieldsAndBody() {
        let doc = Frontmatter.parse("---\ntitle: Code review\ngroup: Coding\n---\n\nReview the diff.")
        #expect(doc.fields["title"] == "Code review")
        #expect(doc.fields["group"] == "Coding")
        #expect(doc.body == "Review the diff.")
    }

    @Test func textWithoutFrontmatterIsAllBody() {
        let doc = Frontmatter.parse("just a plain body\nwith two lines")
        #expect(doc.fields.isEmpty)
        #expect(doc.body == "just a plain body\nwith two lines")
    }

    @Test func valuesKeepColonsAfterTheFirst() {
        let doc = Frontmatter.parse("---\ndescription: Use for ssh:// remotes: be careful\n---\nbody")
        #expect(doc.fields["description"] == "Use for ssh:// remotes: be careful")
    }

    @Test func preservesInternalBlankLinesTrimsEdges() {
        let doc = Frontmatter.parse("---\nname: x\n---\n\nline1\n\nline2\n")
        #expect(doc.body == "line1\n\nline2")
    }

    @Test func missingClosingDelimiterIsTreatedAsPlainBody() {
        let text = "---\ntitle: broken\nno closing fence"
        let doc = Frontmatter.parse(text)
        #expect(doc.fields.isEmpty)
        #expect(doc.body == text)
    }

    @Test func roundTripsThroughRender() {
        let rendered = Frontmatter.render(
            fields: [("title", "Code review"), ("group", "Coding")],
            body: "Review the diff.\n\n- correctness"
        )
        let doc = Frontmatter.parse(rendered)
        #expect(doc.fields["title"] == "Code review")
        #expect(doc.fields["group"] == "Coding")
        #expect(doc.body == "Review the diff.\n\n- correctness")
    }

    @Test func renderEndsWithSingleTrailingNewline() {
        let rendered = Frontmatter.render(fields: [("name", "x")], body: "body")
        #expect(rendered.hasSuffix("body\n"))
        #expect(!rendered.hasSuffix("body\n\n"))
    }
}
