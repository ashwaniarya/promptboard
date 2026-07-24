import Foundation

// Renders a prompt as a minimal Agent Skill. Field rules come from what each tool
// enforces: Codex errors on an empty description and caps name/description length,
// OpenCode silently drops a skill with no name, and an unquoted colon breaks YAML.
public enum SkillExportRenderer {
    public static let nameLimit = 64
    public static let descriptionLimit = 1024

    public struct Export: Equatable, Sendable {
        public let folderName: String
        public let skillMarkdown: String
        public let openAIPolicy: String
    }

    public static func render(_ prompt: Prompt) -> Export {
        let folderName = cappedSlug(from: prompt.title)
        let description = makeDescription(title: prompt.title)
        let markdown = Frontmatter.render(
            fields: [
                ("name", folderName),
                ("description", yamlScalar(description)),
                ("disable-model-invocation", "true"),
            ],
            body: prompt.content
        )
        return Export(folderName: folderName, skillMarkdown: markdown, openAIPolicy: openAIPolicy)
    }

    static func cappedSlug(from title: String) -> String {
        let slug = Slug.make(from: title)
        guard slug.count > nameLimit else { return slug }
        var capped = String(slug.prefix(nameLimit))
        while capped.hasSuffix("-") {
            capped.removeLast()
        }
        return capped.isEmpty ? "untitled" : capped
    }

    static func makeDescription(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let flattened = base.replacingOccurrences(of: "\n", with: " ")
        return String("\(flattened). Saved PromptBoard prompt, user-invoked only.".prefix(descriptionLimit))
    }

    static func yamlScalar(_ value: String) -> String {
        let needsQuoting = value.contains(":") || value.contains("#") || value.hasPrefix(" ")
        guard needsQuoting else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static let openAIPolicy = """
    policy:
      allow_implicit_invocation: false
    """
}
