import Foundation

// Renders a prompt as a minimal Agent Skill. Field rules come from what each tool
// enforces: Codex errors on an empty description and caps name/description length,
// OpenCode silently drops a skill with no name, and YAML forbids raw control
// characters even inside a quoted scalar.
public enum SkillExportRenderer {
    private static let nameLimit = 64
    private static let descriptionLimit = 1024
    private static let descriptionSuffix = ". Saved PromptBoard prompt, user-invoked only."

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

    private static func cappedSlug(from title: String) -> String {
        // Slug.make never returns "" (falls back to "untitled"), never starts with
        // "-", and never emits consecutive "-" runs — so this prefix always starts
        // alphanumeric, and at most one trailing "-" can ever appear here.
        let slug = Slug.make(from: title)
        guard slug.count > nameLimit else { return slug }
        var capped = String(slug.prefix(nameLimit))
        if capped.hasSuffix("-") {
            capped.removeLast()
        }
        return capped
    }

    private static func makeDescription(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let collapsed = collapsingNewlines(in: base)
        let sanitized = replacingControlCharactersWithSpace(in: collapsed)
        let truncated = String(sanitized.prefix(descriptionLimit - descriptionSuffix.count))
        return truncated + descriptionSuffix
    }

    // CharacterSet.newlines also covers U+2028/U+2029, which some YAML parsers
    // treat as line breaks even though Swift doesn't consider them \n or \r.
    private static func collapsingNewlines(in value: String) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasNewline = false
        for scalar in value.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) {
                if !previousWasNewline {
                    scalars.append(" ")
                }
                previousWasNewline = true
            } else {
                scalars.append(scalar)
                previousWasNewline = false
            }
        }
        return String(scalars)
    }

    // Cc only — NOT CharacterSet.controlCharacters, which is Cc *and* Cf and would
    // also strip Cf joiners like ZWJ (U+200D), breaking multi-codepoint emoji.
    private static func replacingControlCharactersWithSpace(in value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            let isIllegalInYAML = scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
            scalars.append(isIllegalInYAML ? " " : scalar)
        }
        return String(scalars)
    }

    private static func quotedScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static let openAIPolicy = """
    policy:
      allow_implicit_invocation: false
    """
}
