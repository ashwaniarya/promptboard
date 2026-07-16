import ArgumentParser
import Foundation
import PromptBoardKit

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List prompts, newest first.")

    @Option(help: "Filter by title/content (case- and diacritic-insensitive).")
    var query: String?

    @Flag(help: "Output JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let prompts = try runHandlingRepositoryErrors {
            try location.repository.loadIfPresent()?.prompts ?? []
        }
        let visible = PromptFilter.filter(prompts, query: query ?? "")
            .sorted { $0.updatedAt > $1.updatedAt }
        if json {
            try Output.printJSON(visible)
        } else {
            for prompt in visible {
                print(Output.listLine(prompt))
            }
        }
    }
}

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print one prompt's content (or full record with --json).")

    @Argument(help: "Prompt id (UUID from `promptboard list`).")
    var id: String

    @Flag(help: "Output JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let promptID = try parsePromptID(id)
        let prompts = try runHandlingRepositoryErrors {
            try location.repository.loadIfPresent()?.prompts ?? []
        }
        guard let prompt = prompts.first(where: { $0.id == promptID }) else {
            printToStandardError("prompt not found: \(promptID.uuidString)")
            throw ExitCode(2)
        }
        if json {
            try Output.printJSON(prompt)
        } else {
            print(prompt.content, terminator: "")
        }
    }
}

struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add a prompt.")

    @Option(help: "Prompt title (defaults to \"Untitled\").")
    var title: String?

    @Option(help: "Prompt text.")
    var content: String?

    @Option(name: .customLong("content-file"), help: "Read prompt text from a file, or - for stdin.")
    var contentFile: String?

    @Flag(help: "Output the created prompt as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func validate() throws {
        if content == nil && contentFile == nil {
            throw ValidationError("provide --content or --content-file")
        }
        if content != nil && contentFile != nil {
            throw ValidationError("--content and --content-file are mutually exclusive")
        }
    }

    func run() throws {
        let body = try resolveContent(inline: content, file: contentFile)
        let mutation = try runHandlingRepositoryErrors {
            try location.repository.add(title: title ?? "", content: body)
        }
        if json {
            try Output.printJSON(mutation.prompt)
        } else {
            print("added \(mutation.prompt.id.uuidString)")
        }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Update a prompt's title and/or content; omitted fields are preserved.")

    @Argument(help: "Prompt id (UUID from `promptboard list`).")
    var id: String

    @Option(help: "New title.")
    var title: String?

    @Option(help: "New prompt text.")
    var content: String?

    @Option(name: .customLong("content-file"), help: "Read new prompt text from a file, or - for stdin.")
    var contentFile: String?

    @Flag(help: "Output the updated prompt as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func validate() throws {
        if content != nil && contentFile != nil {
            throw ValidationError("--content and --content-file are mutually exclusive")
        }
        if title == nil && content == nil && contentFile == nil {
            throw ValidationError("provide --title and/or --content/--content-file")
        }
    }

    func run() throws {
        let promptID = try parsePromptID(id)
        let body: String? = content != nil || contentFile != nil
            ? try resolveContent(inline: content, file: contentFile)
            : nil
        let mutation = try runHandlingRepositoryErrors {
            try location.repository.update(id: promptID, title: title, content: body)
        }
        if json {
            try Output.printJSON(mutation.prompt)
        } else {
            print("updated \(mutation.prompt.id.uuidString)")
        }
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a prompt.")

    @Argument(help: "Prompt id (UUID from `promptboard list`).")
    var id: String

    @Flag(help: "Output the deleted prompt as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let promptID = try parsePromptID(id)
        let mutation = try runHandlingRepositoryErrors {
            try location.repository.delete(id: promptID)
        }
        if json {
            try Output.printJSON(mutation.prompt)
        } else {
            print("deleted \(mutation.prompt.id.uuidString)")
        }
    }
}
