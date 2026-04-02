import ArgumentParser
import Foundation

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a game and all its data (bottle, logs, recipes, etc.)"
    )

    @Argument(help: "Game ID to remove")
    var gameId: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var yes: Bool = false

    mutating func run() throws {
        guard let entry = try CellarStore.findGame(id: gameId) else {
            print("Error: Game '\(gameId)' not found.")
            print("Try this: Run `cellar launch` with no arguments to see available game IDs, or check the web UI at http://localhost:8080")
            throw ExitCode.failure
        }

        if !yes {
            print("Remove '\(entry.name)' and all associated data (bottle, logs, recipes, success records)?")
            print("[y/n] ", terminator: "")
            fflush(stdout)
            guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "y" else {
                print("Aborted.")
                return
            }
        }

        try GameRemover.remove(gameId: gameId)
        print("Removed '\(entry.name)' and all associated data.")
    }
}
