import ArgumentParser

@main
struct Cellar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Wine game launcher for old PC games on macOS",
        subcommands: [StatusCommand.self, AddCommand.self, LaunchCommand.self, LogCommand.self, ServeCommand.self, SyncCommand.self, RemoveCommand.self, InstallAppCommand.self, WikiCommand.self],
        defaultSubcommand: StatusCommand.self
    )

    static func main() async {
        CellarPaths.refuseRoot()
        CellarPaths.checkOwnership()
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }
}
