import Foundation
import Testing
@testable import PromptBoardKit

struct PromptRepositoryTests {
    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBoardRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func loadOnMissingFileReturnsNilAndCreatesNothing() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)

        #expect(try repository.loadIfPresent() == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func addOnMissingFileCreatesExactlyThatPrompt() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)

        let mutation = try repository.add(title: "Solo", content: "body")

        let loaded = try #require(try repository.loadIfPresent())
        #expect(loaded.prompts.count == 1)
        #expect(loaded.prompts.first?.id == mutation.prompt.id)
        #expect(loaded.fileData == mutation.fileData)
    }

    @Test func partialUpdatePreservesOmittedFields() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)
        let added = try repository.add(title: "Original", content: "original body").prompt

        let titleOnly = try repository.update(id: added.id, title: "Renamed", content: nil).prompt
        #expect(titleOnly.title == "Renamed")
        #expect(titleOnly.content == "original body")
        #expect(titleOnly.updatedAt >= added.updatedAt)

        let contentOnly = try repository.update(id: added.id, title: nil, content: "new body").prompt
        #expect(contentOnly.title == "Renamed")
        #expect(contentOnly.content == "new body")
    }

    @Test func updateWithNothingToChangeThrows() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)
        let added = try repository.add(title: "Stays", content: "same").prompt

        do {
            _ = try repository.update(id: added.id, title: nil, content: nil)
            Issue.record("expected nothingToUpdate")
        } catch PromptRepositoryError.nothingToUpdate {}
    }

    @Test func unknownIdThrowsPromptNotFound() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)
        _ = try repository.add(title: "Exists", content: "x")
        let ghostID = UUID()

        do {
            _ = try repository.update(id: ghostID, title: "New", content: nil)
            Issue.record("expected promptNotFound")
        } catch PromptRepositoryError.promptNotFound(let id) {
            #expect(id == ghostID)
        }

        do {
            _ = try repository.delete(id: ghostID)
            Issue.record("expected promptNotFound")
        } catch PromptRepositoryError.promptNotFound {}
    }

    @Test func corruptFileThrowsAndMutationsLeaveItUntouched() throws {
        let directory = makeTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("prompts.json")
        try Data("not json at all {{{".utf8).write(to: fileURL)
        let repository = PromptRepository(directoryURL: directory)

        do {
            _ = try repository.loadIfPresent()
            Issue.record("expected corruptData")
        } catch PromptRepositoryError.corruptData {}

        let bytesBefore = try Data(contentsOf: fileURL)
        do {
            _ = try repository.add(title: "Blocked", content: "x")
            Issue.record("expected corruptData")
        } catch PromptRepositoryError.corruptData {}

        #expect(try Data(contentsOf: fileURL) == bytesBefore)
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!entries.contains { $0.hasPrefix("prompts.json.corrupt-") })
    }

    @Test func concurrentAddsLoseNoWrites() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)

        DispatchQueue.concurrentPerform(iterations: 20) { index in
            _ = try? repository.add(title: "Prompt \(index)", content: "content \(index)")
        }

        let loaded = try #require(try repository.loadIfPresent())
        #expect(loaded.prompts.count == 20)
    }

    @Test func seedRaceNeverDoubleSeeds() throws {
        let directory = makeTemporaryDirectory()
        let repository = PromptRepository(directoryURL: directory)

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 {
                _ = try? repository.seedIfMissing(with: SeedPrompts.samples)
            } else {
                _ = try? repository.add(title: "Racer", content: "x")
            }
        }

        let loaded = try #require(try repository.loadIfPresent())
        #expect(loaded.prompts.contains { $0.title == "Racer" })
        #expect(loaded.prompts.count == 1 || loaded.prompts.count == SeedPrompts.samples.count + 1)
    }

    @Test func encodingContractIsStable() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000.123)
        let prompt = Prompt(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            title: "Fixture",
            content: "body",
            createdAt: fixedDate,
            updatedAt: fixedDate
        )

        let data = try PromptRepository.makeEncoder().encode([prompt])
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("2023-11-14T22:13:20.123Z"))
        let keyPositions = try ["\"content\"", "\"createdAt\"", "\"id\"", "\"title\"", "\"updatedAt\""]
            .map { try #require(json.range(of: $0)).lowerBound }
        #expect(keyPositions == keyPositions.sorted())

        let decoded = try PromptRepository.makeDecoder().decode([Prompt].self, from: data)
        #expect(try PromptRepository.makeEncoder().encode(decoded) == data)
    }
}
