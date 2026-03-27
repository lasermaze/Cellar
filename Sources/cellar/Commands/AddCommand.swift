import ArgumentParser
import Foundation

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a game by running its installer inside a Wine bottle"
    )

    @Argument(help: "Path to the game installer (e.g. setup.exe)")
    var installerPath: String

    mutating func run() throws {
        let installerURL = URL(fileURLWithPath: installerPath)

        // 1. Verify installer exists
        guard FileManager.default.fileExists(atPath: installerURL.path) else {
            print("Error: Installer not found at \(installerPath)")
            throw ExitCode.failure
        }

        // 2. Check dependencies
        let status = DependencyChecker().checkAll()
        guard status.allRequired, let wineURL = status.wine else {
            print("Error: Wine is not installed.")
            print("Run `cellar` first to install dependencies.")
            throw ExitCode.failure
        }

        // 3. Derive game name and ID from installer's parent directory name
        let parentDirName = installerURL.deletingLastPathComponent().lastPathComponent
        let gameName = parentDirName
        let gameId = slugify(parentDirName)

        // 4. Check if game already exists
        if let existing = try? CellarStore.findGame(id: gameId) {
            // findGame returns GameEntry? — nil means not found
            if existing != nil {
                print("Game already added. Use `cellar launch \(gameId)` to play.")
                throw ExitCode.success
            }
        }

        print("Adding game: \(gameName)")

        // 5. Create bottle
        let bottleManager = BottleManager(wineBinary: wineURL)
        _ = try bottleManager.createBottle(gameId: gameId)

        // 6. Run GOG installer inside the bottle
        let wineProcess = WineProcess(
            wineBinary: wineURL,
            winePrefix: CellarPaths.bottleDir(for: gameId)
        )
        print("Running installer inside Wine bottle...")
        try wineProcess.run(
            binary: installerURL.path,
            arguments: ["/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"],
            environment: [:]
        )

        // 7. Save game entry
        let entry = GameEntry(
            id: gameId,
            name: gameName,
            installPath: "",        // determined by recipe executable at launch time
            recipeId: gameId,       // recipe ID matches game ID by convention
            addedAt: Date()
        )
        try CellarStore.addGame(entry)

        print("Game added successfully. Run `cellar launch \(gameId)` to play.")
    }

    // MARK: - Helpers

    /// Convert a directory name to a slug: lowercase, spaces to hyphens, strip non-alphanumeric except hyphens.
    private func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
