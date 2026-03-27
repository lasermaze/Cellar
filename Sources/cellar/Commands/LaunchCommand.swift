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

        // 8. Self-healing retry loop (AGENT-09, AGENT-10, AGENT-11)
        var lastResult: WineResult? = nil
        var lastErrors: [WineError] = []
        var attemptCount = 0
        var allAttempts: [(description: String, environment: [String: String], errors: [WineError])] = []

        var installedDeps: Set<String> = []  // Track installed deps to avoid re-installing
        let maxTotalAttempts = 10  // Cap total attempts across dep installs + variant cycling (raised for AI budget)
        var totalAttempts = 0

        var configIndex = 0
        var aiVariantsGenerated = false
        let originalEnvConfigsCount = envConfigs.count
        var winningConfigIndex = 0  // track which config succeeded

        while (configIndex < envConfigs.count || !aiVariantsGenerated) && totalAttempts < maxTotalAttempts {
            // Phase 3: AI variant injection — when bundled variants exhausted, ask AI for more
            if configIndex >= envConfigs.count && !aiVariantsGenerated {
                aiVariantsGenerated = true

                let history: [(description: String, envDiff: [String: String], errorSummary: String)] = allAttempts.map { attempt in
                    let errorSummary = attempt.errors.map { $0.detail }.joined(separator: "; ")
                    let capped = String(errorSummary.prefix(500))
                    return (description: attempt.description, envDiff: attempt.environment, errorSummary: capped)
                }

                switch AIService.generateVariants(
                    gameId: game,
                    gameName: entry.name,
                    currentEnvironment: recipeEnv,
                    attemptHistory: history
                ) {
                case .success(let aiResult):
                    print("\nAI analysis: \(aiResult.reasoning)")
                    print("Generating \(aiResult.variants.count) alternative configuration(s)...\n")
                    for variant in aiResult.variants {
                        envConfigs.append((description: variant.description, environment: variant.environment))
                    }
                case .unavailable:
                    break  // Silent — no API key is not an error
                case .failed(let msg):
                    print("AI variant generation failed: \(msg)")
                }

                // If no variants were added, exit
                if configIndex >= envConfigs.count {
                    break
                }
            }

            totalAttempts += 1
            attemptCount = totalAttempts
            let config = envConfigs[configIndex]

            if totalAttempts > 1 {
                print("\nAttempt \(totalAttempts): \(config.description)...")
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

            if totalAttempts == 1 {
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

            // Hung launch — treat as failed attempt, advance to next variant
            if result.timedOut {
                let errors = WineErrorParser.parse(result.stderr)
                lastErrors = errors
                allAttempts.append((description: config.description, environment: config.environment, errors: errors))
                print("Launch timed out (no output for 5 minutes). Moving to next variant...")
                configIndex += 1
                if totalAttempts >= maxTotalAttempts { break }
                continue
            }

            // Check if launch succeeded: exit code 0 OR ran for > 2 seconds (game ran)
            if result.exitCode == 0 || result.elapsed > 2.0 {
                winningConfigIndex = configIndex
                break
            }

            // Quick exit — parse errors
            let errors = WineErrorParser.parse(result.stderr)
            lastErrors = errors
            allAttempts.append((description: config.description, environment: config.environment, errors: errors))

            // Check for winetricks fix BEFORE advancing to next variant
            var depInstalled = false
            if let firstFix = errors.compactMap({ error -> String? in
                if case .installWinetricks(let verb) = error.suggestedFix { return verb }
                return nil
            }).first, !installedDeps.contains(firstFix) {
                // Try installing the dep and retry same config
                if let winetricksURL = DependencyChecker().checkAll().winetricks {
                    print("Diagnosed: missing dependency '\(firstFix)'. Installing via winetricks...")
                    let runner = WinetricksRunner(
                        winetricksURL: winetricksURL,
                        wineBinary: wineURL,
                        bottlePath: bottleURL.path
                    )
                    let wtResult = try runner.install(verb: firstFix)
                    installedDeps.insert(firstFix)
                    if wtResult.success {
                        print("Installed \(firstFix). Retrying same configuration...")
                        depInstalled = true
                        // Don't advance configIndex — retry same config with dep installed
                    } else if wtResult.timedOut {
                        print("Warning: \(firstFix) install timed out. Advancing to next variant...")
                    } else {
                        print("Warning: \(firstFix) install failed. Advancing to next variant...")
                    }
                }
            }

            if !depInstalled {
                // AI diagnosis: try when WineErrorParser has no actionable fix
                let hasActionableFix = errors.contains { $0.suggestedFix != nil }
                if !hasActionableFix {
                    let truncatedStderr = String(result.stderr.suffix(8000))
                    switch AIService.diagnose(stderr: truncatedStderr, gameId: game) {
                    case .success(let diagnosis):
                        print("\nAI diagnosis: \(diagnosis.explanation)")
                        if let fix = diagnosis.suggestedFix {
                            // AI suggested a fix -- try to apply it
                            switch fix {
                            case .installWinetricks(let verb):
                                if !installedDeps.contains(verb),
                                   let winetricksURL = DependencyChecker().checkAll().winetricks {
                                    print("AI suggests installing '\(verb)' via winetricks...")
                                    let runner = WinetricksRunner(
                                        winetricksURL: winetricksURL,
                                        wineBinary: wineURL,
                                        bottlePath: bottleURL.path
                                    )
                                    let wtResult = try runner.install(verb: verb)
                                    installedDeps.insert(verb)
                                    if wtResult.success {
                                        print("Installed \(verb). Retrying...")
                                        depInstalled = true
                                    }
                                }
                            case .setEnvVar(let key, let value):
                                // Inject env var into current config for next retry
                                print("AI suggests setting \(key)=\(value)")
                                envConfigs[configIndex].environment[key] = value
                                // Don't advance -- retry same config with new env
                                depInstalled = true  // reuse flag to prevent configIndex advance
                            case .setDLLOverride(let dll, let mode):
                                let key = "WINEDLLOVERRIDES"
                                let override = "\(dll)=\(mode)"
                                let current = envConfigs[configIndex].environment[key] ?? ""
                                let newValue = current.isEmpty ? override : "\(current);\(override)"
                                print("AI suggests DLL override: \(override)")
                                envConfigs[configIndex].environment[key] = newValue
                                depInstalled = true
                            }
                        }
                    case .unavailable:
                        break  // Silent -- no API key is not an error during launch
                    case .failed(let msg):
                        print("AI diagnosis unavailable: \(msg)")
                    }
                }

                if !depInstalled {
                    // No dep installed (or dep already tried) — advance to next variant
                    if errors.isEmpty {
                        print("Wine exited in \(String(format: "%.1f", result.elapsed))s with no diagnosed errors.")
                    } else {
                        print("Diagnosed: \(errors.first!.detail)")
                    }
                    configIndex += 1
                }
            }

            if totalAttempts >= maxTotalAttempts {
                break
            }
        }

        // 9. Post-loop: handle exhausted retries or normal exit

        guard let finalResult = lastResult else {
            print("Error: No launch result available.")
            throw ExitCode.failure
        }

        // Exhausted retries and still failed (AGENT-11)
        if finalResult.elapsed < 2.0 && finalResult.exitCode != 0 && totalAttempts >= maxTotalAttempts {
            print("\n--- Launch Failed ---")
            print("Exhausted \(totalAttempts) attempt(s). Summary:")
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
