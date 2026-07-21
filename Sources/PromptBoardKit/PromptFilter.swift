import Foundation

public enum PromptFilter {
    public static func filter(_ prompts: [Prompt], query: String) -> [Prompt] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return prompts }
        return prompts.filter { prompt in
            matches(prompt.title, trimmedQuery) || matches(prompt.content, trimmedQuery)
        }
    }

    public static func filter(_ items: [LibraryEntry], query: String) -> [LibraryEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }
        return items.filter { item in
            switch item {
            case .prompt(let prompt):
                matches(prompt.title, trimmedQuery) || matches(prompt.content, trimmedQuery)
            case .skill(let skill):
                matches(skill.name, trimmedQuery)
                    || matches(skill.description, trimmedQuery)
                    || matches(skill.body, trimmedQuery)
            }
        }
    }

    private static func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
