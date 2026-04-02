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
            print("Try this: Run `cellar` to install Wine and other dependencies.")
            throw ExitCode.failure
        }

        // Pre-flight: check permissions (advisory only)
        PermissionChecker.printWarningsIfNeeded()

        // 2. Find game
        guard var entry = try CellarStore.findGame(id: game) else {
            print("Error: Game '\(game)' not found.")
            print("Try this: Run `cellar add /path/to/installer.exe` to add a game first.")
            throw ExitCode.failure
        }

        // 3. Check bottle exists
        let bottleManager = BottleManager(wineBinary: wineURL)
        guard bottleManager.bottleExists(gameId: game) else {
            print("Error: Bottle for '\(game)' not found.")
            print("Try this: Run `cellar add /path/to/installer.exe` to reinstall the game.")
            throw ExitCode.failure
        }

        let bottleURL = CellarPaths.bottleDir(for: game)
        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: bottleURL)

        // 4. Resolve executable path
        let executablePath: String
        if let stored = entry.executablePath {
            executablePath = stored
        } else if let recipe = try RecipeEngine.findBundledRecipe(for: game) {
            let discovered = BottleScanner.scanForExecutables(bottlePath: bottleURL)
            if let found = BottleScanner.findExecutable(named: recipe.executable, in: discovered) {
                executablePath = found.path
            } else if let first = discovered.first {
                executablePath = first.path
            } else {
                print("Error: No executables found in bottle for '\(game)'.")
                print("Try this: Run `cellar add /path/to/installer.exe` to reinstall the game.")
                throw ExitCode.failure
            }
        } else {
            print("Error: No executable path stored and no recipe available.")
            print("Try this: Run `cellar add /path/to/installer.exe` to re-add the game with a working installer.")
            throw ExitCode.failure
        }

        // 5. Try agent loop (requires Anthropic API key)
        switch AIService.runAgentLoop(
            gameId: game,
            entry: entry,
            executablePath: executablePath,
            wineURL: wineURL,
            bottleURL: bottleURL,
            wineProcess: wineProcess
        ) {
        case .success(let summary):
            // Agent completed — it handled launch, user interaction, and recipe saving
            print(summary)
            entry.lastLaunched = Date()
            try CellarStore.updateGame(entry)
            return

        case .unavailable:
            // No API key — fall back to recipe-only launch
            print("No AI API key configured. Launching with recipe defaults only.")
            try recipeFallbackLaunch(
                entry: &entry,
                executablePath: executablePath,
                wineProcess: wineProcess,
                wineURL: wineURL,
                bottleURL: bottleURL
            )

        case .failed(let msg):
            print("\n--- Agent stopped ---")
            if msg.contains("[STOP:budget]") {
                print("Reason: \(msg.replacingOccurrences(of: "[STOP:budget] ", with: ""))")
            } else if msg.contains("[STOP:iterations]") {
                print("Reason: \(msg.replacingOccurrences(of: "[STOP:iterations] ", with: ""))")
            } else if msg.contains("[STOP:api_error]") {
                print("Reason: \(msg.replacingOccurrences(of: "[STOP:api_error] ", with: ""))")
            } else {
                print("Reason: \(msg)")
            }
            print("Falling back to recipe-only launch...")
            try recipeFallbackLaunch(
                entry: &entry,
                executablePath: executablePath,
                wineProcess: wineProcess,
                wineURL: wineURL,
                bottleURL: bottleURL
            )
        }
    }

    // MARK: - Fallback

    /// Single-launch recipe-only path for when no Anthropic API key is configured or the agent fails.
    /// One launch attempt, one validation prompt — no retry loop, no AI.
    private mutating func recipeFallbackLaunch(
        entry: inout GameEntry,
        executablePath: String,
        wineProcess: WineProcess,
        wineURL: URL,
        bottleURL: URL
    ) throws {
        // Load recipe and apply it
        let recipe = try RecipeEngine.findBundledRecipe(for: game)
        var recipeEnv: [String: String] = [:]
        if let recipe = recipe {
            recipeEnv = try RecipeEngine().apply(recipe: recipe, wineProcess: wineProcess)
        }

        // Prepare log file
        let launchTimestamp = Date()
        let logFileURL = CellarPaths.logFile(for: game, timestamp: launchTimestamp)
        try FileManager.default.createDirectory(
            at: CellarPaths.logDir(for: game),
            withIntermediateDirectories: true
        )
        print("Log: \(logFileURL.path)")

        // Set up SIGINT handler — Ctrl+C kills wineserver but still shows validation prompt
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            try? wineProcess.killWineserver()
        }
        sigintSource.resume()

        print("Launching \(game)...")
        let result = try wineProcess.run(
            binary: executablePath,
            arguments: recipe?.launchArgs ?? [],
            environment: recipeEnv,
            logFile: logFileURL
        )

        sigintSource.cancel()
        signal(SIGINT, SIG_DFL)

        // Ask user how it went
        let validation = ValidationPrompt.run(
            gameId: game,
            elapsed: result.elapsed,
            wineProcess: wineProcess
        )

        let reachedMenu = validation?.reachedMenu ?? false
        entry.lastLaunched = Date()
        entry.lastResult = LaunchResult(
            timestamp: Date(),
            reachedMenu: reachedMenu,
            attemptCount: 1,
            diagnosis: nil
        )
        try CellarStore.updateGame(entry)
    }
}
