import Foundation

public enum PromptFilter {
    public static func filter(_ prompts: [Prompt], query: String) -> [Prompt] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return prompts }
        return prompts.filter { prompt in
            matches(prompt.title, trimmedQuery) || matches(prompt.content, trimmedQuery)
        }
    }

    private static func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
