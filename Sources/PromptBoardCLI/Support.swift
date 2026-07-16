import ArgumentParser
import Foundation
import PromptBoardKit

func runHandlingRepositoryErrors<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let error as PromptRepositoryError {
        printToStandardError(repositoryErrorMessage(for: error))
        throw ExitCode(exitCode(for: error))
    }
}

func parsePromptID(_ raw: String) throws -> UUID {
    guard let id = UUID(uuidString: raw) else {
        throw ValidationError("invalid prompt id (expected a UUID from `promptboard list`): \(raw)")
    }
    return id
}

func resolveContent(inline: String?, file: String?) throws -> String {
    if let inline {
        return inline
    }
    guard let file else {
        throw ValidationError("provide --content or --content-file")
    }
    if file == "-" {
        return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }
    do {
        return try String(contentsOfFile: (file as NSString).expandingTildeInPath, encoding: .utf8)
    } catch {
        printToStandardError("cannot read --content-file: \(error.localizedDescription)")
        throw ExitCode(1)
    }
}

func printToStandardError(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

func repositoryErrorMessage(for error: PromptRepositoryError) -> String {
    switch error {
    case .corruptData(let path, _):
        "corrupt prompts file (fix or remove it): \(path)"
    case .promptNotFound(let id):
        "prompt not found: \(id.uuidString)"
    case .nothingToUpdate:
        "nothing to update: pass --title and/or --content/--content-file"
    case .lockTimeout(let path):
        "timed out waiting for the library lock: \(path)"
    case .ioFailure(let underlying):
        "I/O failure: \(underlying.localizedDescription)"
    }
}

private func exitCode(for error: PromptRepositoryError) -> Int32 {
    switch error {
    case .promptNotFound: 2
    case .corruptData: 3
    case .nothingToUpdate: 64
    case .lockTimeout, .ioFailure: 1
    }
}

enum Output {
    static func printJSON(_ value: some Encodable) throws {
        let data = try PromptRepository.makeEncoder().encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    static func listLine(_ prompt: Prompt) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(prompt.id.uuidString)\t\(prompt.title)\t\(formatter.string(from: prompt.updatedAt))"
    }
}
