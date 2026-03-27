import ArgumentParser

@main
struct Cellar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Wine game launcher for old PC games on macOS",
        subcommands: [StatusCommand.self, AddCommand.self, LaunchCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
