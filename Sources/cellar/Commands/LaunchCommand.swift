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

        // 6. Determine executable path using GameEntry.executablePath (AGENT-06 consumer)
        let executablePath: String
        if let stored = entry.executablePath {
            // Use the path discovered during `cellar add`
            executablePath = stored
        } else if let recipe = recipe {
            // Fallback: construct from recipe + assumed GOG path (legacy entries without executablePath)
            let gogDir = bottleURL.path + "/drive_c/GOG Games/Cossacks - European Wars"
            executablePath = gogDir + "/" + recipe.executable
        } else {
            print("Error: No executable path stored and no recipe available.")
            print("Re-add the game with `cellar add /path/to/installer`.")
            throw ExitCode.failure
        }

        // 7. Build the list of env configurations to try (base + retry variants)
        var envConfigs: [(description: String, environment: [String: String])] = []
        envConfigs.append((description: "Base recipe configuration", environment: recipeEnv))
        if let variants = recipe?.retryVariants {
            for variant in variants {
                envConfigs.append((description: variant.description, environment: variant.environment))
            }
        }
        let maxAttempts = min(envConfigs.count, 3)  // cap at 3 per AGENT-09

        // 8. Self-healing retry loop (AGENT-09, AGENT-10, AGENT-11)
        var lastResult: WineResult? = nil
        var lastErrors: [WineError] = []
        var attemptCount = 0
        var allAttempts: [(description: String, errors: [WineError])] = []

        for attempt in 0..<maxAttempts {
            attemptCount = attempt + 1
            let config = envConfigs[attempt]

            if attempt > 0 {
                print("\nTrying variant \(attempt + 1)/\(maxAttempts): \(config.description)...")
            }

            // Prepare log file for this attempt
            let launchTimestamp = Date()
            let logFileURL = CellarPaths.logFile(for: game, timestamp: launchTimestamp)
            try FileManager.default.createDirectory(
                at: CellarPaths.logDir(for: game),
                withIntermediateDirectories: true
            )
            print("Log: \(logFileURL.path)")

            // Set up SIGINT handler — Ctrl+C kills Wine but still shows validation prompt
            // WineProcess.run() is synchronous; we use wineserver -k for Wine-aware termination
            signal(SIGINT, SIG_IGN)
            let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sigintSource.setEventHandler {
                try? wineProcess.killWineserver()
            }
            sigintSource.resume()

            if attempt == 0 {
                print("Launching \(game)...")
            }

            let result = try wineProcess.run(
                binary: executablePath,
                arguments: recipe?.launchArgs ?? [],
                environment: config.environment,
                logFile: logFileURL
            )

            sigintSource.cancel()
            signal(SIGINT, SIG_DFL)

            lastResult = result

            // Check if launch succeeded: exit code 0 OR ran for > 2 seconds (game ran)
            if result.exitCode == 0 || result.elapsed > 2.0 {
                break
            }

            // Quick exit — parse errors and decide whether to retry
            let errors = WineErrorParser.parse(result.stderr)
            lastErrors = errors
            allAttempts.append((description: config.description, errors: errors))

            if errors.isEmpty {
                print("Wine exited in \(String(format: "%.1f", result.elapsed))s with no diagnosed errors.")
                if attempt < maxAttempts - 1 {
                    print("Retrying with alternative configuration...")
                }
            } else {
                print("Diagnosed: \(errors.first!.detail)")
            }

            // If this is the last attempt, stop
            if attempt == maxAttempts - 1 {
                break
            }
        }

        // 9. Post-loop: handle exhausted retries or normal exit

        guard let finalResult = lastResult else {
            print("Error: No launch result available.")
            throw ExitCode.failure
        }

        // Exhausted retries and still failed (AGENT-11)
        if finalResult.elapsed < 2.0 && finalResult.exitCode != 0 && attemptCount >= maxAttempts {
            print("\n--- Launch Failed ---")
            print("Exhausted \(attemptCount) attempt(s). Summary:")
            for (i, attempt) in allAttempts.enumerated() {
                print("  Attempt \(i + 1): \(attempt.description)")
                if attempt.errors.isEmpty {
                    print("    No specific errors diagnosed")
                } else {
                    for error in attempt.errors {
                        print("    - \(error.detail)")
                    }
                }
            }
            if let bestDiagnosis = lastErrors.first {
                print("\nBest diagnosis: \(bestDiagnosis.detail)")
                if let fix = bestDiagnosis.suggestedFix {
                    switch fix {
                    case .installWinetricks(let verb):
                        print("Suggested fix: Install '\(verb)' via winetricks")
                    case .setEnvVar(let key, let value):
                        print("Suggested fix: Set \(key)=\(value)")
                    case .setDLLOverride(let dll, let mode):
                        print("Suggested fix: Set DLL override \(dll)=\(mode)")
                    }
                }
            }
            print("\nCheck the latest log for details: \(CellarPaths.logDir(for: game).path)")

            // Record the failed result
            entry.lastLaunched = Date()
            entry.lastResult = LaunchResult(
                timestamp: Date(),
                reachedMenu: false,
                attemptCount: attemptCount,
                diagnosis: lastErrors.first?.detail
            )
            try CellarStore.updateGame(entry)
            return
        }

        // Normal post-exit: validation prompt
        let reachedMenu = ValidationPrompt.run(
            gameId: game,
            elapsed: finalResult.elapsed,
            wineProcess: wineProcess
        )

        if let reachedMenu = reachedMenu {
            entry.lastLaunched = Date()
            entry.lastResult = LaunchResult(
                timestamp: Date(),
                reachedMenu: reachedMenu,
                attemptCount: attemptCount,
                diagnosis: lastErrors.isEmpty ? nil : lastErrors.first?.detail
            )
            try CellarStore.updateGame(entry)
            print("Launch result recorded.")
        }
    }
}
