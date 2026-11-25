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
            case .chain(let chain):
                matches(chain.title, trimmedQuery) || matches(chain.customStepText, trimmedQuery)
            }
        }
    }

    public static func filter(_ items: [ExternalItem], query: String) -> [ExternalItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }
        return items.filter {
            matches($0.name, trimmedQuery) || matches($0.origin, trimmedQuery)
                || matches($0.description, trimmedQuery)
        }
    }

    private static func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    // Ranking for the cursor quick-insert popup over prompts and chains (skills dropped).
    // The slug (recomputed from the title) doubles as a `/alias`. Ranked, best first:
    // exact alias, alias prefix, title substring, content substring. Stable within a tier.
    // A chain's content is its custom step text; linked prompt content is not searched.
    public static func quickInsertResults(_ entries: [LibraryEntry], query: String) -> [LibraryEntry] {
        let insertable = entries.filter { $0.kind != .skill }
        var normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("/") { normalized.removeFirst() }
        guard !normalized.isEmpty else { return insertable }

        func rank(_ entry: LibraryEntry) -> Int? {
            let content: String
            switch entry {
            case .prompt(let prompt): content = prompt.content
            case .chain(let chain): content = chain.customStepText
            case .skill: return nil
            }
            let alias = Slug.make(from: entry.title)
            if alias == normalized { return 0 }
            if alias.hasPrefix(normalized) { return 1 }
            if matches(entry.title, normalized) { return 2 }
            if matches(content, normalized) { return 3 }
            return nil
        }

        return insertable
            .enumerated()
            .compactMap { index, entry in rank(entry).map { (index: index, tier: $0, entry: entry) } }
            .sorted { $0.tier != $1.tier ? $0.tier < $1.tier : $0.index < $1.index }
            .map(\.entry)
    }
}
