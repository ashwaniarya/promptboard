import Foundation
import Observation

@MainActor
@Observable
public final class PromptStore {
    public private(set) var prompts: [Prompt] = []

    private let directoryURL: URL
    private let fileURL: URL

    public static var defaultDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptBoard", isDirectory: true)
    }

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appendingPathComponent("prompts.json")
        load()
    }

    @discardableResult
    public func add(title: String, content: String) -> Prompt {
        let prompt = Prompt(title: normalizedTitle(title), content: content)
        prompts.append(prompt)
        persist()
        return prompt
    }

    public func update(id: UUID, title: String, content: String) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        prompts[index].title = normalizedTitle(title)
        prompts[index].content = content
        prompts[index].updatedAt = Date()
        persist()
    }

    public func delete(id: UUID) {
        prompts.removeAll { $0.id == id }
        persist()
    }

    private func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            seed()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            prompts = try Self.makeDecoder().decode([Prompt].self, from: data)
        } catch {
            quarantineCorruptFile()
            seed()
        }
    }

    private func seed() {
        prompts = SeedPrompts.samples
        persist()
    }

    private func quarantineCorruptFile() {
        let epoch = Int(Date().timeIntervalSince1970)
        let backupURL = directoryURL.appendingPathComponent("prompts.json.corrupt-\(epoch)")
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(prompts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("PromptStore persist failed: \(error)\n".utf8))
        }
    }

    // Plain .iso8601 truncates to whole seconds, which breaks updatedAt ordering across relaunches
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawDate = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plainFormatter = ISO8601DateFormatter()
            plainFormatter.formatOptions = [.withInternetDateTime]
            guard let date = fractionalFormatter.date(from: rawDate) ?? plainFormatter.date(from: rawDate) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(rawDate)"
                )
            }
            return date
        }
        return decoder
    }
}
