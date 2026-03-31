import ArgumentParser

@main
struct Cellar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Wine game launcher for old PC games on macOS",
        subcommands: [StatusCommand.self, AddCommand.self, LaunchCommand.self, LogCommand.self, ServeCommand.self, SyncCommand.self],
        defaultSubcommand: StatusCommand.self
    )

    static func main() throws {
        CellarPaths.refuseRoot()
        CellarPaths.checkOwnership()
        var command = try Self.parseAsRoot()
        try command.run()
    }
}
