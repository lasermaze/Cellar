import ArgumentParser

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show dependency status and installed games"
    )

    mutating func run() {
        // Stub — implemented in a later plan
        print("cellar status: not yet implemented")
    }
}
