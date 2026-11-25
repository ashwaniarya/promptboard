import ArgumentParser
import Foundation
import PromptBoardKit

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List prompts, skills and chains, newest first.")

    @Option(help: "Filter by title/content (case- and diacritic-insensitive).")
    var query: String?

    @Option(help: "Only items of this kind: prompt, skill or chain.")
    var type: String?

    @Option(help: "Only items in this group.")
    var group: String?

    @Flag(help: "Output JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func validate() throws {
        if let type, LibraryEntry.Kind(rawValue: type) == nil {
            throw ValidationError("--type must be prompt, skill or chain")
        }
    }

    func run() throws {
        let items = try withLibrary(location) { try $0.load().items }
        var visible = PromptFilter.filter(items, query: query ?? "")
        if let type { visible = visible.filter { $0.kind.rawValue == type } }
        if let group { visible = visible.filter { $0.group == group } }
        visible.sort { $0.updatedAt > $1.updatedAt }

        if json {
            try Output.printJSON(visible)
        } else {
            for item in visible {
                print(Output.listLine(item))
            }
        }
    }
}

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print an item's content: a prompt's text, or a skill's SKILL.md (or one of its files)."
    )

    @Argument(help: "Item id (UUID from `promptboard list`).")
    var id: String

    @Option(name: .customLong("file"), help: "For a skill, print this supporting file instead of SKILL.md.")
    var file: String?

    @Flag(name: .customLong("list-files"), help: "For a skill, list its supporting files.")
    var listFiles = false

    @Flag(help: "Output the full record as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let itemID = try parseItemID(id)
        try withLibrary(location) { repository in
            guard let item = try repository.load().items.first(where: { $0.id == itemID }) else {
                printToStandardError("not found: \(itemID.uuidString)")
                throw ExitCode(2)
            }
            switch item {
            case .prompt(let prompt):
                if json { try Output.printJSON(item) } else { print(prompt.content, terminator: "") }
            case .skill(let skill):
                if listFiles {
                    for supportingFile in skill.files { print(supportingFile.relativePath) }
                } else if let file {
                    FileHandle.standardOutput.write(try repository.skillFileData(id: itemID, relativePath: file))
                } else if json {
                    try Output.printJSON(item)
                } else {
                    print(skill.body, terminator: "")
                }
            case .chain(let chain):
                if json { try Output.printJSON(item) } else { print(ChainBody.render(chain.steps)) }
            }
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

    @Option(help: "Group to file it under.")
    var group: String?

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
        let prompt = try withLibrary(location) {
            try $0.addPrompt(title: title ?? "", content: body, group: group)
        }
        if json { try Output.printJSON(LibraryEntry.prompt(prompt)) } else { print("added \(prompt.id.uuidString)") }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update a prompt's title, content, and/or group; omitted fields are preserved."
    )

    @Argument(help: "Prompt id (UUID from `promptboard list`).")
    var id: String

    @Option(help: "New title.")
    var title: String?

    @Option(help: "New prompt text.")
    var content: String?

    @Option(name: .customLong("content-file"), help: "Read new prompt text from a file, or - for stdin.")
    var contentFile: String?

    @Option(help: "New group.")
    var group: String?

    @Flag(help: "Output the updated prompt as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func validate() throws {
        if content != nil && contentFile != nil {
            throw ValidationError("--content and --content-file are mutually exclusive")
        }
        if title == nil && content == nil && contentFile == nil && group == nil {
            throw ValidationError("provide --title, --content/--content-file, and/or --group")
        }
    }

    func run() throws {
        let itemID = try parseItemID(id)
        let body: String? = content != nil || contentFile != nil
            ? try resolveContent(inline: content, file: contentFile)
            : nil
        let prompt = try withLibrary(location) {
            try $0.updatePrompt(id: itemID, title: title, content: body, group: group)
        }
        if json { try Output.printJSON(LibraryEntry.prompt(prompt)) } else { print("updated \(prompt.id.uuidString)") }
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a prompt or skill by id.")

    @Argument(help: "Item id (UUID from `promptboard list`).")
    var id: String

    @Flag(help: "Output the deleted item as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let itemID = try parseItemID(id)
        let deleted: LibraryEntry = try withLibrary(location) { repository in
            do {
                return .prompt(try repository.deletePrompt(id: itemID))
            } catch LibraryRepositoryError.promptNotFound {
                return .skill(try repository.deleteSkill(id: itemID))
            }
        }
        if json { try Output.printJSON(deleted) } else { print("deleted \(deleted.id.uuidString)") }
    }
}

struct ImportSkill: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-skill",
        abstract: "Import an Agent Skill folder (containing SKILL.md) into the library and link it into ~/.claude/skills."
    )

    @Argument(help: "Path to a skill folder containing SKILL.md.")
    var path: String

    @Option(help: "Group to file it under.")
    var group: String?

    @Flag(help: "Output the imported skill as JSON.")
    var json = false

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        let skill = try withLibrary(location) { try $0.importSkill(fromDirectory: source, group: group) }
        if json {
            try Output.printJSON(LibraryEntry.skill(skill))
        } else {
            print("imported \(skill.name) (\(skill.id.uuidString))")
        }
    }
}

struct Relink: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Re-establish ~/.claude/skills symlinks for every library skill (no-clobber)."
    )

    @OptionGroup var location: DataDirectoryOptions

    func run() throws {
        let linked = try withLibrary(location) { try $0.relinkAllSkills() }
        print("linked \(linked) skill(s)")
    }
}
