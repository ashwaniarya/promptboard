import ArgumentParser
import Foundation
import PromptBoardKit

// Opens the library, migrates a legacy prompts.json once (so agents see existing
// prompts even before the app has ever launched), then runs the body — mapping
// repository errors to messages + exit codes.
func withLibrary<T>(_ location: DataDirectoryOptions, _ body: (LibraryRepository) throws -> T) throws -> T {
    let repository = location.repository
    return try runHandlingRepositoryErrors {
        _ = try repository.migrateLegacyIfNeeded()
        return try body(repository)
    }
}

func runHandlingRepositoryErrors<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let error as LibraryRepositoryError {
        printToStandardError(repositoryErrorMessage(for: error))
        throw ExitCode(exitCode(for: error))
    }
}

func parseItemID(_ raw: String) throws -> UUID {
    guard let id = UUID(uuidString: raw) else {
        throw ValidationError("invalid id (expected a UUID from `promptboard list`): \(raw)")
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

func repositoryErrorMessage(for error: LibraryRepositoryError) -> String {
    switch error {
    case .promptNotFound(let id):
        "prompt not found: \(id.uuidString)"
    case .skillNotFound(let id):
        "skill not found: \(id.uuidString)"
    case .chainNotFound(let id):
        "chain not found: \(id.uuidString)"
    case .nothingToUpdate:
        "nothing to update: pass a field to change"
    case .lockTimeout(let path):
        "timed out waiting for the library lock: \(path)"
    case .ioFailure(let underlying):
        "I/O failure: \(underlying.localizedDescription)"
    case .skillLinkConflict(let name, let path):
        "skill \(name) not linked: \(path) already exists and isn't ours"
    case .invalidSkillSource(let path):
        "not a valid skill folder (needs SKILL.md): \(path)"
    }
}

private func exitCode(for error: LibraryRepositoryError) -> Int32 {
    switch error {
    case .promptNotFound, .skillNotFound, .chainNotFound: 2
    case .nothingToUpdate, .invalidSkillSource: 64
    case .lockTimeout, .ioFailure, .skillLinkConflict: 1
    }
}

enum Output {
    static func printJSON(_ value: some Encodable) throws {
        let data = try CanonicalJSON.makeEncoder().encode(value)
        print(String(decoding: data, as: UTF8.self))
    }

    static func listLine(_ item: LibraryEntry) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return "\(item.id.uuidString)\t\(item.kind.rawValue)\t\(item.title)\t\(formatter.string(from: item.updatedAt))"
    }
}
