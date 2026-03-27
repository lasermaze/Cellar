import ArgumentParser

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a game by running its installer inside a Wine bottle"
    )

    @Argument(help: "Path to the game installer (e.g. setup.exe)")
    var installerPath: String

    mutating func run() {
        // Stub — implemented in a later plan
        print("cellar add: not yet implemented")
    }
}
