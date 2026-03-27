import ArgumentParser
import Foundation

struct LaunchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an installed game via Wine"
    )

    @Argument(help: "Game name or ID to launch")
    var game: String

    mutating func run() throws {
        // 1. Check dependencies
        let status = DependencyChecker().checkAll()
        guard status.allRequired, let wineURL = status.wine else {
            print("Error: Wine is not installed.")
            print("Run `cellar` first to install dependencies.")
            throw ExitCode.failure
        }

        // 2. Find game
        guard var entry = try CellarStore.findGame(id: game) else {
            print("Game not found. Run `cellar add /path/to/installer` first.")
            throw ExitCode.failure
        }

        // 3. Check bottle exists
        let bottleManager = BottleManager(wineBinary: wineURL)
        guard bottleManager.bottleExists(gameId: game) else {
            print("Error: Bottle for '\(game)' not found. Run `cellar add /path/to/installer` again.")
            throw ExitCode.failure
        }

        let bottleURL = CellarPaths.bottleDir(for: game)
        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: bottleURL)

        // 4. Load recipe
        let recipe = try RecipeEngine.findBundledRecipe(for: game)
        if recipe == nil {
            print("Warning: No recipe found for \(game). Launching with default Wine settings.")
        }

        // 5. Apply recipe (if found)
        var recipeEnv: [String: String] = [:]
        if let recipe = recipe {
            recipeEnv = try RecipeEngine().apply(recipe: recipe, wineProcess: wineProcess)
        }

        // 6. Prepare log file
        let launchTimestamp = Date()
        let logFileURL = CellarPaths.logFile(for: game, timestamp: launchTimestamp)
        // Create log directory — WineProcess.run() will create the file, but let's ensure directory exists
        try FileManager.default.createDirectory(
            at: CellarPaths.logDir(for: game),
            withIntermediateDirectories: true
        )
        print("Log: \(logFileURL.path)")

        // 7. Set up SIGINT handler — Ctrl+C kills Wine but still shows validation prompt
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)

        // WineProcess.run() is synchronous and doesn't expose the Process object externally,
        // so we rely on wineserver -k to terminate Wine processes in this prefix.
        // After wineserver kills the game, the readabilityHandler EOF causes run() to return.
        sigintSource.setEventHandler {
            // Send SIGTERM to all wine processes in this prefix via wineserver -k
            try? wineProcess.killWineserver()
        }
        sigintSource.resume()

        // 8. Determine executable path
        // GOG installers for Cossacks place the game at:
        // C:\GOG Games\Cossacks - European Wars\{executable}
        // Under Wine this is {bottleURL}/drive_c/GOG Games/Cossacks - European Wars/{executable}
        let executablePath: String
        if let recipe = recipe {
            // Build the full Unix path to the Windows executable inside the bottle
            let gogDir = bottleURL.path + "/drive_c/GOG Games/Cossacks - European Wars"
            executablePath = gogDir + "/" + recipe.executable
        } else {
            print("Error: Cannot determine game executable without a recipe.")
            sigintSource.cancel()
            signal(SIGINT, SIG_DFL)
            throw ExitCode.failure
        }

        print("Launching \(game)...")
        let startTime = Date()

        // run() streams stdout/stderr to terminal AND writes to log file simultaneously
        try wineProcess.run(
            binary: executablePath,
            arguments: recipe?.launchArgs ?? [],
            environment: recipeEnv,
            logFile: logFileURL
        )

        // 9. Post-exit flow
        let elapsed = Date().timeIntervalSince(startTime)
        sigintSource.cancel()
        signal(SIGINT, SIG_DFL)

        let result = ValidationPrompt.run(
            gameId: game,
            elapsed: elapsed,
            wineProcess: wineProcess
        )

        if let result = result {
            entry.lastLaunched = Date()
            entry.lastResult = result
            try CellarStore.updateGame(entry)
            print("Launch result recorded.")
        }
    }
}
