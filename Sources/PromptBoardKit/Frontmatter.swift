import Foundation

// Minimal, dependency-free frontmatter for our own `.md` files: a leading `---`
// fence, `key: value` lines (split on the first colon so values keep theirs),
// a closing `---`, then the markdown body. Not a general YAML parser — values
// are single-line strings, which is all prompts/skills need.
public enum Frontmatter {
    public struct Document: Equatable, Sendable {
        public var fields: [String: String]
        public var body: String

        public init(fields: [String: String], body: String) {
            self.fields = fields
            self.body = body
        }
    }

    public static func parse(_ text: String) -> Document {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return Document(fields: [:], body: text)
        }

        var fields: [String: String] = [:]
        var index = 1
        var foundClosing = false
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                foundClosing = true
                index += 1
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    fields[key] = value
                }
            }
            index += 1
        }

        guard foundClosing else {
            return Document(fields: [:], body: text)
        }
        let body = lines[index...].joined(separator: "\n").trimmingCharacters(in: .newlines)
        return Document(fields: fields, body: body)
    }

    public static func render(fields: [(String, String)], body: String) -> String {
        var output = "---\n"
        for (key, value) in fields {
            output += "\(key): \(value)\n"
        }
        output += "---\n"
        let trimmedBody = body.trimmingCharacters(in: .newlines)
        if !trimmedBody.isEmpty {
            output += "\n\(trimmedBody)\n"
        }
        return output
    }
}
