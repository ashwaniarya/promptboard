import Foundation

public enum SeedPrompts {
    public static var samples: [Prompt] {
        [
            Prompt(
                title: "Explain Like I'm 5",
                content: "Explain the following concept like I'm five years old. Use a simple analogy, avoid jargon, and end with a one-sentence summary:\n\n"
            ),
            Prompt(
                title: "Code Review",
                content: "Review this code for bugs, readability, and performance. List issues by severity, quote the exact line, and suggest a concrete fix for each:\n\n"
            ),
            Prompt(
                title: "Meeting Summarizer",
                content: "Summarize these meeting notes into:\n1. Key decisions\n2. Action items with owners\n3. Open questions\n\nKeep it under 150 words.\n\n"
            ),
            Prompt(
                title: "Brainstorm 10 Ideas",
                content: "Give me 10 unconventional ideas for the topic below. For each one: a one-line pitch, why it might work, and its biggest risk. Rank them by impact at the end.\n\nTopic: "
            ),
            Prompt(
                title: "Rewrite Professionally",
                content: "Rewrite the following message so it is professional, warm, and concise.\n\nRules:\n- Keep it under 120 words\n- No corporate buzzwords\n- Preserve all facts, names, and dates\n- Match the original intent\n- End with a clear call to action\n\nMessage:\n"
            ),
        ]
    }
}
