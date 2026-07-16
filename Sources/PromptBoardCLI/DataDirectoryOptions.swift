import ArgumentParser
import Foundation
import PromptBoardKit

struct DataDirectoryOptions: ParsableArguments {
    @Option(
        name: .customLong("data-dir"),
        help: "Directory containing prompts.json (default: $PROMPTBOARD_DATA_DIR, else ~/Library/Application Support/PromptBoard)"
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
        return PromptRepository.defaultDirectoryURL
    }

    var repository: PromptRepository {
        PromptRepository(directoryURL: resolvedDirectoryURL)
    }
}
