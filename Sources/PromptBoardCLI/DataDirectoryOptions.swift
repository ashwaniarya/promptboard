import ArgumentParser
import Foundation
import PromptBoardKit

struct DataDirectoryOptions: ParsableArguments {
    @Option(
        name: .customLong("data-dir"),
        help: "Library directory (default: $PROMPTBOARD_DATA_DIR, else ~/Library/Application Support/PromptBoard)"
    )
    var dataDir: String?

    var resolvedDirectoryURL: URL {
        if let dataDir {
            return URL(fileURLWithPath: (dataDir as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let environmentPath = ProcessInfo.processInfo.environment["PROMPTBOARD_DATA_DIR"],
           !environmentPath.isEmpty {
            return URL(fileURLWithPath: environmentPath, isDirectory: true)
        }
        return LibraryRepository.defaultDirectoryURL
    }

    var repository: LibraryRepository {
        let claudeSkillsURL = ProcessInfo.processInfo.environment["PROMPTBOARD_CLAUDE_SKILLS_DIR"]
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? LibraryRepository.defaultClaudeSkillsURL
        return LibraryRepository(directoryURL: resolvedDirectoryURL, claudeSkillsURL: claudeSkillsURL)
    }
}
