import ArgumentParser

struct LaunchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an installed game via Wine"
    )

    @Argument(help: "Game name or ID to launch")
    var game: String

    mutating func run() {
        // Stub — implemented in a later plan
        print("cellar launch: not yet implemented")
    }
}
