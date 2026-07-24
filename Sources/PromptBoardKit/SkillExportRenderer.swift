import Foundation

// Renders a prompt as a minimal Agent Skill. Field rules come from what each tool
// enforces: Codex errors on an empty description and caps name/description length,
// OpenCode silently drops a skill with no name. `name` and `description` are always
// double-quoted rather than quoted only when "risky" characters appear: YAML plain
// scalars break on more than `:`/`#` (leading `[`, `"`, `!`, `>`, `-`, etc. are also
// indicators, and bare `no`/`yes`/`123` parse as non-strings), so quoting
// unconditionally is the only rule that removes the whole bug class instead of
// chasing individual characters.
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
                ("name", quotedScalar(folderName)),
                ("description", quotedScalar(description)),
                ("disable-model-invocation", "true"),
            ],
            body: prompt.content
        )
        return Export(folderName: folderName, skillMarkdown: markdown, openAIPolicy: openAIPolicy)
    }

    static func cappedSlug(from title: String) -> String {
        // Slug.make never returns "" (falls back to "untitled"), never starts with
        // "-", and never emits consecutive "-" runs — so this prefix always starts
        // alphanumeric, and stripping a trailing "-" can never empty it.
        let slug = Slug.make(from: title)
        guard slug.count > nameLimit else { return slug }
        var capped = String(slug.prefix(nameLimit))
        while capped.hasSuffix("-") {
            capped.removeLast()
        }
        return capped
    }

    static func makeDescription(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let flattened = base
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        // Control characters (NUL, ESC, DEL, ...) are illegal in YAML even inside a
        // quoted scalar, so quoting alone doesn't make them safe.
        let sanitized = stripControlCharacters(from: flattened)
        return String("\(sanitized). Saved PromptBoard prompt, user-invoked only.".prefix(descriptionLimit))
    }

    static func stripControlCharacters(from value: String) -> String {
        let space: Unicode.Scalar = " "
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            scalars.append(CharacterSet.controlCharacters.contains(scalar) ? space : scalar)
        }
        return String(scalars)
    }

    static func quotedScalar(_ value: String) -> String {
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
