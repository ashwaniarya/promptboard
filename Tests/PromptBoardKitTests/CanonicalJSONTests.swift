import Foundation
import Testing
@testable import PromptBoardKit

struct CanonicalJSONTests {
    @Test func encodesFractionalISO8601AndSortsKeys() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000.123)
        let prompt = Prompt(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Fixture",
            content: "body",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let data = try CanonicalJSON.makeEncoder().encode([prompt])
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("2023-11-14T22:13:20.123Z"))
        let keyPositions = try ["\"content\"", "\"createdAt\"", "\"id\"", "\"title\"", "\"updatedAt\""]
            .map { try #require(json.range(of: $0)).lowerBound }
        #expect(keyPositions == keyPositions.sorted())

        let decoded = try CanonicalJSON.makeDecoder().decode([Prompt].self, from: data)
        #expect(try CanonicalJSON.makeEncoder().encode(decoded) == data)
    }

    @Test func decoderAcceptsWholeSecondTimestamps() throws {
        let json = Data(#"["2023-11-14T22:13:20Z"]"#.utf8)
        let dates = try CanonicalJSON.makeDecoder().decode([Date].self, from: json)
        #expect(dates.count == 1)
    }
}
