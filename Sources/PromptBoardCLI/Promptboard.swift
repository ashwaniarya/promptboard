import ArgumentParser

@main
struct Promptboard: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "promptboard",
        abstract: "Manage the PromptBoard prompt library from the command line or over MCP.",
        subcommands: [List.self, Get.self, Add.self, Update.self, Delete.self, ImportSkill.self, Relink.self, MCP.self]
    )
}
